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
HISTORICAL = ['resolving-merge-conflicts']
OBSOLETE = ['diagnose', 'zoom-out']
KEPT = ['pr']
RETIRED = [name for name in KNOWN + HISTORICAL + OBSOLETE if name not in KEPT]


def embedded(script):
    text = (ROOT / script).read_text()
    if script == 'win.ps1':
        return text.split("    $helper = @'\n", 1)[1].split("\n'@", 1)[0]
    return text.split("<<'MANAGED_SKILL_POLICY_JS'\n", 1)[1].split('\nMANAGED_SKILL_POLICY_JS', 1)[0]


def functions(script):
    text = (ROOT / script).read_text()
    if script == 'win.ps1':
        names = ['Invoke-MattPocockSkillPolicy', 'Remove-MattPocockSkills', 'Setup-MattPocockSkills',
                 'Set-PiSkillOwnership', 'Remove-PrLensSkill', 'Remove-SimpleEnglishSkill', 'Remove-ShowMeSkill']
        pattern = lambda name: r'^function ' + name + r' \{.*?^\}'
    else:
        names = ['matt_pocock_skill_policy', 'remove_matt_pocock_skills', 'setup_matt_pocock_skills',
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
            'NODE_OPTIONS', 'NODE_PATH', 'WORK_MACHINE')}
        self.env.update(HOME=str(self.home), USERPROFILE=str(self.home), SKILL_TEST_CALLS=str(self.root / 'calls'),
                        TMPDIR=str(self.root), TMP=str(self.root), TEMP=str(self.root),
                        XDG_CACHE_HOME=str(self.root / 'cache'), XDG_CONFIG_HOME=str(self.root / 'config'),
                        XDG_DATA_HOME=str(self.root / 'data'))
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

    def policy(self, mode, success=True, blocked=False, script='mac.sh'):
        helper = self.root / 'policy.cjs'
        helper.write_text(embedded(script))
        proc = subprocess.run([NODE, str(helper), str(self.home), self.env.get('PI_CODING_AGENT_DIR', ''),
                               '1' if blocked else '0', mode], env=self.env, text=True, capture_output=True, timeout=30)
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
function npm { [IO.File]::WriteAllText($env:SKILL_TEST_CALLS, 'npm'); throw 'unexpected npm call' }
function npx { [IO.File]::WriteAllText($env:SKILL_TEST_CALLS, 'npx'); throw 'unexpected npx call' }
''' + f'$script:PiProfileMutationsBlocked=${str(blocked).lower()}\n$result = {action}\n'
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
print_error() { printf '%s\n' "$1" >&2; }
npm() { : > "${SKILL_TEST_CALLS}"; return 90; }
npx() { : > "${SKILL_TEST_CALLS}"; return 90; }
''' + f'\nPI_PROFILE_MUTATIONS_BLOCKED={int(blocked)}\n{action}\n')
            command = ['bash', str(fixture)]
        proc = subprocess.run(command, env=self.env, cwd=self.root, text=True, capture_output=True, timeout=30)
        self.assertEqual(proc.returncode == 0, success, script + ': ' + proc.stdout + proc.stderr)
        self.assertNotIn('PRIVATE-SENTINEL', proc.stdout + proc.stderr)
        self.assertFalse(Path(self.env['SKILL_TEST_CALLS']).exists(), 'retirement must not run the skills CLI')
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
            for retired in ('setup_pr_lens_skill', 'Install-PrLensSkill', 'coldteadotai/pr-lens',
                            'setup_simple_english_skill', 'Install-SimpleEnglishSkill', 'AminBlg/SimpleEnglish',
                            'setup_show_me_skill', 'Install-ShowMeSkill', 'humanlayer/skills',
                            "--skill '*'", 'BAN_SCOWALT_ENGINEERING_SKILLS', 'BAN_MATT_POCOCK_SKILLS',
                            'BAN_MATT_POCKOCK_SKILLS', 'Test-MattPocockSkillsDisabled', 'matt_pocock_skills_disabled'):
                self.assertNotIn(retired, text, script)
            if script != 'win.ps1':
                self.assertRegex(text, r'remove_show_me_skill(?:; then| \|\| _setup_had_errors=1)')
                self.assertRegex(text, r'remove_simple_english_skill(?:; then| \|\| _setup_had_errors=1)')
                self.assertRegex(text, r'remove_pr_lens_skill(?:; then| \|\| _setup_had_errors=1)')
                self.assertRegex(text, r'setup_matt_pocock_skills(?:; then| \|\| _setup_had_errors=1)')
            else:
                self.assertIn('if (-not (Remove-PrLensSkill))', text)
                self.assertIn('if (-not (Remove-SimpleEnglishSkill))', text)
                self.assertIn('if (-not (Remove-ShowMeSkill))', text)
                self.assertIn('Setup-MattPocockSkills', text)
        self.assertEqual(len(KNOWN), 37)
        for name in KNOWN + HISTORICAL + OBSOLETE + KEPT:
            self.assertIn("'" + name + "'", baseline)

    def test_every_wrapper_retires_suite_but_keeps_pr_and_unrelated_data(self):
        self.env['XDG_STATE_HOME'] = str(self.home / 'state')
        manifest = self.home / '.agents/.setup-matt-pocock-skills.json'
        locks = [self.home / '.agents/.skill-lock.json', self.home / 'state/skills/.skill-lock.json']
        tracked = {'old-future': 'mattpocock/skills', 'fork-future': 'scowalt/engineering-skills'}
        sentinels = [self.put(self.home / name, 'PRIVATE-SENTINEL') for name in (
            '.env.local', 'project/.agents/skills/tdd/SKILL.md', '.claude/hooks/keep')]
        for script in SCRIPTS:
            if script == 'win.ps1' and not PWSH:
                continue
            for work in ('0', '1'):
                with self.subTest(script=script, work=work):
                    self.env['WORK_MACHINE'] = work
                    self.put(manifest, json.dumps({'version': 1, 'skills': ['inventory-only', 'pr']}))
                    for lock in locks:
                        self.put(lock, json.dumps({'version': 3, 'skills': {
                            **{name: {'source': source} for name, source in tracked.items()},
                            'tdd': {'source': 'scowalt/engineering-skills'},
                            'pr': {'source': 'scowalt/engineering-skills'},
                            'keep': {'source': 'other/repo'}}, 'dismissed': {'keep': True}}))
                    names = RETIRED + ['inventory-only', *tracked]
                    for base in self.all_dirs():
                        for name in names:
                            self.put(base / name / 'references/guide.md', 'user-modified managed copy')
                        self.put(base / 'pr/SKILL.md', 'dotfiles-managed pr')
                        self.put(base / 'keep-me/SKILL.md', 'unrelated skill')
                    for _ in range(2):
                        self.wrapper(script)
                    for base in self.all_dirs():
                        self.assertEqual(sorted(p.name for p in base.iterdir()), ['keep-me', 'pr'], base)
                        self.assertEqual((base / 'pr/SKILL.md').read_text(), 'dotfiles-managed pr')
                    for lock in locks:
                        self.assertEqual(json.loads(lock.read_text()), {'version': 3, 'skills': {
                            'keep': {'source': 'other/repo'}}, 'dismissed': {'keep': True}})
                    self.assertEqual(json.loads(manifest.read_text())['skills'], ['inventory-only', 'pr'])
        for sentinel in sentinels:
            self.assertEqual(sentinel.read_text(), 'PRIVATE-SENTINEL')

    def test_retirement_keeps_unrelated_pr_lock_records(self):
        lock = self.put(self.home / '.agents/.skill-lock.json', json.dumps({'version': 3, 'skills': {
            'pr': {'source': 'scowalt/dotfiles'}, 'tdd': {'source': 'mattpocock/skills'}}}))
        self.policy('remove-matt')
        self.assertEqual(json.loads(lock.read_text())['skills'], {'pr': {'source': 'scowalt/dotfiles'}})

    def test_group_writable_containers_retire_without_mode_repair(self):
        self.env['XDG_STATE_HOME'] = str(self.home / 'state')
        state = self.put(self.home / 'state/skills/.skill-lock.json', json.dumps({
            'version': 3, 'skills': {'keep': {'source': 'other/repo'}, 'tdd': {'source': 'mattpocock/skills'}},
            'dismissed': {'keep': True}}))
        for base in self.all_dirs():
            self.put(base / 'keep-me/SKILL.md', 'unrelated skill')
            self.put(base / 'tdd/SKILL.md', 'retired copy')
        private = {self.default_pi, self.custom_pi}
        containers = [self.home] + [p for p in self.home.rglob('*') if p.is_dir() and p.name != 'tdd']
        for directory in containers:
            directory.chmod(0o700 if directory in private else 0o2775)
        metadata = {p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode, p.stat().st_ino) for p in containers}
        for script in ('mac.sh', 'win.ps1'):
            if script == 'win.ps1' and not PWSH:
                continue
            with self.subTest(script=script):
                for _ in range(2):
                    self.wrapper(script)
                    self.wrapper(script, 'ownership')
                for base in self.all_dirs():
                    self.assertEqual([p.name for p in base.iterdir()], ['keep-me'])
                self.assertEqual(json.loads(state.read_text()), {
                    'version': 3, 'skills': {'keep': {'source': 'other/repo'}}, 'dismissed': {'keep': True}})
                self.assertEqual({p: (p.stat().st_uid, p.stat().st_gid, p.stat().st_mode, p.stat().st_ino)
                                  for p in containers}, metadata)

    def test_default_claude_path_is_covered(self):
        self.env.pop('CLAUDE_CONFIG_DIR')
        self.put(self.home / '.claude/skills/retro/SKILL.md')
        self.put(self.home / '.claude/skills/pr/SKILL.md')
        self.wrapper('mac.sh')
        self.assertFalse((self.home / '.claude/skills/retro').exists())
        self.assertTrue((self.home / '.claude/skills/pr/SKILL.md').is_file())

    def test_ownership_deduplicates_only_dotfiles_managed_pr(self):
        self.put(self.shared / 'pr/SKILL.md', 'dotfiles pr')
        self.put(self.shared / 'tdd/SKILL.md', 'unrelated shared copy')
        for script in ('mac.sh', 'win.ps1'):
            if script == 'win.ps1' and not PWSH:
                continue
            with self.subTest(script=script):
                self.put(self.default_pi / 'skills/pr/SKILL.md', 'dotfiles pr')
                self.put(self.custom_pi / 'skills/pr/SKILL.md', 'user-modified pr')
                for profile in (self.default_pi, self.custom_pi):
                    self.put(profile / 'skills/prototype/SKILL.md', 'Pi-local prototype')
                    self.put(profile / 'settings.json', '{"theme":"keep","skills":["custom"]}')
                for _ in range(2):
                    self.wrapper(script, 'ownership')
                self.assertFalse((self.default_pi / 'skills/pr').exists())
                self.assertEqual((self.custom_pi / 'skills/pr/SKILL.md').read_text(), 'user-modified pr')
                for profile in (self.default_pi, self.custom_pi):
                    self.assertEqual((profile / 'skills/prototype/SKILL.md').read_text(), 'Pi-local prototype')
                    settings = json.loads((profile / 'settings.json').read_text())
                    self.assertEqual(settings['theme'], 'keep')
                    self.assertIn('custom', settings['skills'])
                    self.assertEqual(settings['skills'].count('!' + str(profile / 'skills/pr') + '/**'), 1)
                    self.assertFalse(any('prototype' in rule or '/tdd/' in rule for rule in settings['skills']))

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

    def test_suite_retirement_rejects_unsafe_metadata_and_linked_ancestors_before_removal(self):
        keep = self.put(self.shared / 'tdd/SKILL.md')
        for content in ('PRIVATE-SENTINEL malformed', '{"version":2,"skills":["tdd"]}', '{"version":1,"skills":["../x"]}'):
            with self.subTest(inventory=content):
                manifest = self.put(self.home / '.agents/.setup-matt-pocock-skills.json', content)
                self.policy('remove-matt', success=False)
                self.assertTrue(keep.is_file())
                manifest.unlink()
        lock = self.put(self.home / '.agents/.skill-lock.json', 'PRIVATE-SENTINEL malformed')
        self.policy('remove-matt', success=False)
        self.assertTrue(keep.is_file())
        lock.unlink()
        target = self.put(self.home / 'lock-target.json', '{"version":3,"skills":{}}')
        lock.symlink_to(target)
        self.policy('remove-matt', success=False)
        self.assertTrue(keep.is_file())
        lock.unlink()
        linked = self.put(self.home / 'sentinel/tdd/SKILL.md', 'PRIVATE-SENTINEL').parent.parent
        (self.home / '.gemini').mkdir()
        (self.home / '.gemini/skills').symlink_to(linked, target_is_directory=True)
        for script in ('mac.sh', 'win.ps1'):
            if script == 'win.ps1' and not PWSH:
                continue
            self.wrapper(script, success=False)
            self.assertTrue(keep.is_file())
            self.assertEqual((linked / 'tdd/SKILL.md').read_text(), 'PRIVATE-SENTINEL')

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

    def test_all_three_retirements_preserve_other_skills_on_personal_and_work_machines(self):
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
                    for base in self.all_dirs():
                        self.put(base / 'pr/SKILL.md', 'dotfiles-managed pr')
                        for skill in retired:
                            self.put(base / skill / 'SKILL.md', 'user-modified retired skill')
                        self.put(base / 'keep-me/SKILL.md', 'keep unrelated skill')
                    shutil.rmtree(self.shared / 'show-me')
                    (self.shared / 'show-me').symlink_to(sentinel.parent, target_is_directory=True)
                    for profile in (self.default_pi, self.custom_pi):
                        for skill in retired:
                            (profile / 'skills' / (skill + '.md')).symlink_to(self.home / 'missing-target.md')
                    expected_locks = {}
                    for lock in locks:
                        data = json.loads(lock.read_text()) if lock.exists() else {
                            'version': 3, 'skills': {'keep': {'source': 'other/repo'}}, 'dismissed': {'keep': True}}
                        expected_locks[lock] = json.loads(json.dumps(data))
                        data['skills'].update({skill: {'source': source} for skill, (_, source) in retired.items()})
                        self.put(lock, json.dumps(data))
                    for _ in range(2):
                        for operation, _source in retired.values():
                            self.wrapper(script, operation)
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
                    self.assertEqual((self.shared / 'pr/SKILL.md').read_text(), 'dotfiles-managed pr')
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
        command = [NODE, '--require', str(shim), str(helper), str(alias / 'account'), '', '0', 'remove-matt']
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

    def test_retirement_removes_leaf_links_without_following_targets_or_touching_projects(self):
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

    def test_ownership_rejects_linked_shared_root_and_malformed_settings_before_removal(self):
        for profile in (self.default_pi, self.custom_pi):
            self.put(profile / 'skills/pr/SKILL.md', 'matching')
        self.put(self.shared / 'pr/SKILL.md', 'matching')
        settings = self.put(self.custom_pi / 'settings.json', 'PRIVATE-SENTINEL malformed')
        self.policy('ownership', success=False)
        self.assertTrue((self.default_pi / 'skills/pr/SKILL.md').exists())
        settings.write_text('{}')
        target = self.home / 'linked-shared'
        self.shared.rename(target)
        self.shared.symlink_to(target, target_is_directory=True)
        self.policy('ownership', success=False)
        self.assertTrue((self.default_pi / 'skills/pr/SKILL.md').exists())

    @unittest.skipUnless(os.environ.get('PI_SKILLS_DOTFILES_SOURCE'), 'Set PI_SKILLS_DOTFILES_SOURCE for render/setup coverage')
    def test_dotfiles_render_agrees_with_setup_ownership(self):
        source = Path(os.environ['PI_SKILLS_DOTFILES_SOURCE'])
        template = source / 'private_dot_pi/agent/private_settings.json.tmpl'
        empty_source = self.home / 'empty-source'
        empty_source.mkdir()
        config = self.put(self.home / 'chezmoi.json', '{}')
        self.put(self.home / '.agents/.setup-matt-pocock-skills.json', json.dumps({'version': 1, 'skills': ['tdd']}))
        self.put(self.shared / 'pr/SKILL.md', 'dotfiles pr')
        self.env.pop('PI_CODING_AGENT_DIR')
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
                self.assertEqual(settings['skills'].count('!' + str(self.default_pi / 'skills/pr') + '/**'), 1)
                for retired in ('/tdd/', 'pr-lens', 'simple-english', 'show-me'):
                    self.assertNotIn(retired, result.stdout)
                self.assertIn('npm:pi-claude-bridge', settings['packages'])
                self.put(self.default_pi / 'settings.json', result.stdout)
                self.assertTrue((self.shared / 'pr/SKILL.md').is_file())


if __name__ == '__main__':
    unittest.main()
