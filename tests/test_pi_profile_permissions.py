"""Extracted, offline directory preparation fixtures; never run setup or Pi."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1')
NODE = shutil.which('node')
PWSH = os.environ.get('PWSH_BIN') or shutil.which('pwsh')
BEGIN = '// BEGIN PI_PROFILE_PERMISSIONS'
END = '// END PI_PROFILE_PERMISSIONS'


def metadata(stat):
    # Reading assertions may update atime under relatime; it is not a setup write.
    return (stat.st_mode, stat.st_ino, stat.st_dev, stat.st_nlink, stat.st_uid,
            stat.st_gid, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)


def extracted_functions(script, select):
    import re
    text = (ROOT / script).read_text()
    pattern = r'^function ([\w-]+) \{' if script == 'win.ps1' else r'^(\w+)\(\) \{'
    bodies = []
    for match in re.finditer(pattern, text, re.M):
        if select(match[1]):
            bodies.append(text[match.start():text.index('\n}\n', match.end()) + 2])
    assert bodies, (script, select)
    return '\n'.join(bodies)


def embedded(script):
    text = (ROOT / script).read_text()
    assert BEGIN in text, f'{script}: directory preparation helper missing'
    return text[text.index(BEGIN):text.index(END) + len(END)]


class ProfilePermissionsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pi-permissions-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir(mode=0o700)
        self.profile = self.home / '.pi/agent'
        self.env = {'PATH': os.environ['PATH'], 'HOME': str(self.home), 'USERPROFILE': str(self.home)}
        for name in ('SystemRoot', 'WINDIR', 'TEMP', 'TMP'):
            if name in os.environ:
                self.env[name] = os.environ[name]

    def helper(self, active='', script='ubuntu.sh', prelude=''):
        file = self.root / 'helper.cjs'
        file.write_text(prelude + embedded(script))
        result = subprocess.run([NODE, str(file), str(self.home), str(active)], env=self.env,
                                cwd=self.root, capture_output=True, text=True, timeout=30)
        self.assertNotIn(str(self.home), result.stdout + result.stderr)
        self.assertNotIn('PRIVATE-SENTINEL', result.stdout + result.stderr)
        return result

    def create_profile(self):
        self.profile.mkdir(parents=True)
        self.profile.parent.chmod(0o775)
        self.profile.chmod(0o775)

    @unittest.skipIf(os.name == 'nt', 'POSIX mode regression')
    def test_arcane_0775_is_repaired_without_touching_contents_or_home(self):
        self.create_profile()
        auth = self.profile / 'auth.json'
        auth.write_text('{"fixture":"PRIVATE-SENTINEL"}')
        auth.chmod(0o600)
        dependency = self.profile / 'npm/node_modules/example'
        dependency.mkdir(parents=True)
        dependency.chmod(0o775)
        before = (auth.read_bytes(), metadata(auth.stat()), metadata(self.home.stat()), metadata(dependency.stat()))
        for _ in range(2):
            result = self.helper()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(self.profile.stat().st_mode & 0o777, 0o700)
            self.assertEqual(self.profile.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual((auth.read_bytes(), metadata(auth.stat()), metadata(self.home.stat()), metadata(dependency.stat())), before)

    def test_copies_creation_custom_leaf_and_idempotence(self):
        bodies = [embedded(script) for script in SCRIPTS]
        self.assertTrue(all(body == bodies[0] for body in bodies))
        custom_parent = self.home / 'profiles'
        custom_parent.mkdir(mode=0o750)
        parent_before = custom_parent.stat().st_mode
        active = custom_parent / 'custom'
        for script in SCRIPTS:
            result = self.helper(active, script)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for directory in (self.profile.parent, self.profile, active):
                self.assertTrue(directory.is_dir())
                if os.name != 'nt':
                    self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
            self.assertEqual(custom_parent.stat().st_mode, parent_before)

    def test_all_profiles_preflight_before_default_creation_or_repair(self):
        outside = self.root / 'outside'
        outside.mkdir()
        linked = self.home / 'linked'
        linked.symlink_to(outside, target_is_directory=True)
        file = self.home / 'not-a-directory'
        file.write_text('PRIVATE-SENTINEL')
        bad = [outside, self.home, 'relative/profile', str(self.home) + '/../escape',
               linked, linked / 'child', file, self.home / 'missing-parent/child']
        for active in bad:
            with self.subTest(active=str(active)):
                result = self.helper(active)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.profile.parent.exists())
        self.create_profile()
        for active in bad:
            result = self.helper(active)
            self.assertNotEqual(result.returncode, 0)
            if os.name != 'nt':
                self.assertEqual(self.profile.stat().st_mode & 0o777, 0o775)
                self.assertEqual(self.profile.parent.stat().st_mode & 0o777, 0o775)

    @unittest.skipIf(os.name == 'nt', 'POSIX ownership and ancestor modes')
    def test_foreign_profile_and_unsafe_ancestor_are_not_repaired(self):
        self.create_profile()
        active_parent = self.home / 'profiles'
        active_parent.mkdir(mode=0o775)
        active_parent.chmod(0o775)
        active = active_parent / 'active'
        active.mkdir(mode=0o775)
        result = self.helper(active)
        self.assertIn('failed:unsafe-ancestor', result.stdout)
        self.assertEqual(self.profile.stat().st_mode & 0o777, 0o775)
        active_parent.chmod(0o755)
        # OS stat seam simulates another owner without sudo or a real chown.
        prelude = "const fixtureFs = require('node:fs'); const fixtureStat = fixtureFs.lstatSync;\n"
        prelude += "fixtureFs.lstatSync = (file, ...args) => { const s = fixtureStat(file, ...args); if (file === process.argv[3]) s.uid = process.getuid() + 1; return s; };\n"
        result = self.helper(active, prelude=prelude)
        self.assertIn('failed:foreign-owner', result.stdout)
        self.assertEqual(self.profile.stat().st_mode & 0o777, 0o775)
        self.home.chmod(0o775)
        result = self.helper()
        self.assertIn('failed:unsafe-ancestor', result.stdout)
        self.assertEqual(self.home.stat().st_mode & 0o777, 0o775)

    def test_linked_default_rejects_before_active_repair(self):
        outside = self.root / 'outside'
        outside.mkdir()
        (self.home / '.pi').symlink_to(outside, target_is_directory=True)
        active = self.home / 'active'
        active.mkdir(mode=0o775)
        active.chmod(0o775)
        result = self.helper(active)
        self.assertNotEqual(result.returncode, 0)
        if os.name != 'nt':
            self.assertEqual(active.stat().st_mode & 0o777, 0o775)
        self.assertEqual(list(outside.iterdir()), [])

    def test_metadata_remains_untouched_for_existing_validators(self):
        self.create_profile()
        outside = self.root / 'metadata'
        outside.write_text('PRIVATE-SENTINEL')
        for name in ('auth.json', 'models.json', 'settings.json'):
            target = self.profile / name
            for linked in (False, True):
                if linked:
                    target.symlink_to(outside)
                else:
                    target.write_text('malformed PRIVATE-SENTINEL')
                before = metadata(target.lstat())
                result = self.helper()
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(metadata(target.lstat()), before)
                self.assertEqual(target.read_text(), 'PRIVATE-SENTINEL' if linked else 'malformed PRIVATE-SENTINEL')
                target.unlink()

    @unittest.skipIf(os.name == 'nt', 'Arcane POSIX regression with offline Go catalog/lock')
    def test_arcane_go_rejection_is_fixed_without_relaxing_go_validation(self):
        from test_pi_opencode_go_setup import GoSetupTests
        fixture = GoSetupTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        fixture.profile.mkdir(parents=True)
        fixture.profile.parent.chmod(0o775)
        fixture.profile.chmod(0o775)
        before = fixture.run_helper()
        self.assertNotEqual(before.returncode, 0)
        self.assertIn('active-profile:untrusted-directory', before.stdout)
        file = self.root / 'prepare.cjs'
        file.write_text(embedded('ubuntu.sh'))
        result = subprocess.run([NODE, str(file), str(fixture.home), ''], env=fixture.env,
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout)
        after = fixture.run_helper()
        self.assertEqual(after.returncode, 0, after.stdout)
        self.assertEqual(after.stdout.strip(), 'updated')

    def test_prose_still_rejects_malformed_or_linked_metadata_after_preparation(self):
        self.create_profile()
        source = (ROOT / 'ubuntu.sh').read_text()
        start = source.index('// BEGIN PI_PROSE_RETIREMENT')
        end = source.index('// END PI_PROSE_RETIREMENT') + len('// END PI_PROSE_RETIREMENT')
        file = self.root / 'retirement.cjs'
        file.write_text(source[start:end])
        outside = self.root / 'settings'
        outside.write_text('{"packages":["npm:pi-prose"],"keep":"PRIVATE-SENTINEL"}')
        settings = self.profile / 'settings.json'
        for linked in (False, True):
            if linked:
                settings.symlink_to(outside)
            else:
                settings.write_text('malformed PRIVATE-SENTINEL')
            self.assertEqual(self.helper().returncode, 0)
            before = (metadata(settings.lstat()), settings.read_bytes(), outside.read_bytes())
            result = subprocess.run([NODE, str(file), str(self.home), ''], env=self.env,
                                    text=True, capture_output=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('PRIVATE-SENTINEL', result.stdout + result.stderr)
            self.assertEqual((metadata(settings.lstat()), settings.read_bytes(), outside.read_bytes()), before)
            settings.unlink()

    @unittest.skipIf(os.name == 'nt', 'POSIX creation race at the OS boundary')
    def test_parent_swap_or_disappearance_cannot_redirect_or_recreate_leaf_creation(self):
        import json
        for action in ('swap', 'disappear'):
            with self.subTest(action=action):
                parent = self.home / '.pi'
                if parent.is_symlink():
                    parent.unlink()
                parent.mkdir(mode=0o700)
                outside = self.root / ('outside-' + action)
                outside.mkdir(mode=0o700)
                moved = self.home / ('moved-' + action)
                prelude = 'const fixtureParent = ' + json.dumps(str(parent)) + ';\n'
                prelude += 'const fixtureOutside = ' + json.dumps(str(outside)) + ';\n'
                prelude += 'const fixtureMoved = ' + json.dumps(str(moved)) + ';\n'
                prelude += 'const fixtureAction = ' + json.dumps(action) + ';\n'
                prelude += r'''
const fixtureFs = require('node:fs'), fixtureChild = require('node:child_process');
let fixtureRaced = false;
function fixtureRace() {
    if (fixtureRaced) return;
    fixtureRaced = true;
    if (fixtureAction === 'swap') {
        fixtureFs.renameSync(fixtureParent, fixtureMoved);
        fixtureFs.symlinkSync(fixtureOutside, fixtureParent);
    } else fixtureFs.rmdirSync(fixtureParent);
}
const fixtureMkdir = fixtureFs.mkdirSync;
fixtureFs.mkdirSync = (file, ...args) => {
    if (file === fixtureParent + '/agent') fixtureRace();
    return fixtureMkdir(file, ...args);
};
const fixtureSpawn = fixtureChild.spawnSync;
fixtureChild.spawnSync = (exe, args, ...rest) => {
    if (exe.endsWith('/python3') && args.includes('agent')) fixtureRace();
    return fixtureSpawn(exe, args, ...rest);
};
process.on('exit', () => { if (!fixtureRaced) { process.stdout.write('race-not-exercised'); process.exitCode = 2; } });
'''
                result = self.helper(prelude=prelude)
                self.assertNotIn('race-not-exercised', result.stdout)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(list(outside.iterdir()), [])
                if action == 'swap':
                    self.assertTrue(parent.is_symlink())
                    parent.unlink()
                else:
                    self.assertFalse(parent.exists())

    @unittest.skipIf(os.name == 'nt', 'POSIX mkdirat leaf-name contract')
    def test_creation_probe_word_is_a_valid_profile_name(self):
        active = self.home / 'probe'
        result = self.helper(active)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(active.is_dir())

    @unittest.skipIf(os.name == 'nt', 'POSIX mkdirat capability preflight')
    def test_unavailable_descriptor_relative_creation_defers_before_any_chmod(self):
        self.create_profile()
        active = self.home / 'new-profile'
        prelude = "require('node:child_process').spawnSync = () => ({status:1, stdout:'PRIVATE-SENTINEL', stderr:'PRIVATE-SENTINEL'});\n"
        result = self.helper(active, prelude=prelude)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), 'failed:directory-create-unavailable')
        self.assertFalse(active.exists())
        self.assertEqual(self.profile.parent.stat().st_mode & 0o777, 0o775)
        self.assertEqual(self.profile.stat().st_mode & 0o777, 0o775)

    def test_windows_creation_and_acl_changes_require_pinned_stable_handles(self):
        code = embedded('win.ps1')
        self.assertNotIn('[IO.Directory]::CreateDirectory', code)
        self.assertIn('NtCreateFile', code)
        self.assertIn('RootDirectory', code)
        self.assertIn('FILE_CREATE', code)
        self.assertIn('FILE_SHARE_READ', code)
        for part in ('Volume', 'IndexHigh', 'IndexLow'):
            self.assertIn('before.' + part + ' == after.' + part, code)

    @unittest.skipIf(os.name == 'nt', 'POSIX injected kernel errors')
    def test_kernel_failure_stays_controlled_and_does_not_rewrite_credentials(self):
        self.create_profile()
        auth = self.profile / 'auth.json'
        auth.write_text('PRIVATE-SENTINEL')
        prelude = "require('node:fs').fchmodSync = () => { throw Object.assign(Error('PRIVATE-SENTINEL'), {code:'EROFS'}); };\n"
        result = self.helper(prelude=prelude)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), 'failed:EROFS')
        self.assertEqual(auth.read_text(), 'PRIVATE-SENTINEL')
        self.assertEqual(self.profile.stat().st_mode & 0o777, 0o775)

    def test_failure_gate_precedes_all_pi_mutations(self):
        for script in SCRIPTS:
            text = (ROOT / script).read_text()
            if script == 'win.ps1':
                main = text[text.index('function Invoke-WindowsSetupTasks {'):]
                self.assertLess(main.index('Prepare-PiProfilePermissions'), main.index('Remove-RtkResources'))
                self.assertLess(main.index('Prepare-PiProfilePermissions'), main.index('Remove-PiProse'))
                self.assertIn('$script:PiProfileMutationsBlocked = $true', main)
            else:
                main = text[text.index('run_setup_tasks() {'):]
                self.assertLess(main.index('prepare_pi_profile_permissions'), main.index('remove_rtk_resources'))
                self.assertLess(main.index('prepare_pi_profile_permissions'), main.index('remove_pi_prose'))
                self.assertIn('PI_PROFILE_MUTATIONS_BLOCKED=1', main)


    def test_blocked_pi_skill_cleanup_preserves_pi_but_continues_shared_cleanup(self):
        for script in SCRIPTS:
            if script == 'win.ps1' and not PWSH:
                continue
            with self.subTest(script=script):
                if not self.profile.exists():
                    self.create_profile()
                pi_skill = self.profile / 'skills/impeccable'
                shared_skill = self.home / '.agents/skills/impeccable'
                for directory in (pi_skill, shared_skill):
                    directory.mkdir(parents=True, exist_ok=True)
                    (directory / 'SKILL.md').write_text('PRIVATE-SENTINEL')
                settings = self.profile / 'settings.json'
                settings.write_text('malformed PRIVATE-SENTINEL')
                text = (ROOT / script).read_text()
                windows = script == 'win.ps1'
                names = ('Set-PiSkillOwnership', 'Remove-ImpeccableResources') if windows else ('configure_pi_skill_ownership', 'remove_impeccable_resources')
                bodies = []
                for name in names:
                    signature = 'function ' + name + ' {' if windows else name + '() {'
                    start = text.index(signature)
                    bodies.append(text[start:text.index('\n}\n', start) + 2])
                if windows:
                    fixture = self.root / 'blocked.ps1'
                    fixture.write_text("$ErrorActionPreference='Stop'\n$script:PiProfileMutationsBlocked=$true\n"
                                       "function Write-Warning($Message) {}\nfunction Write-Success($Message) {}\nfunction Write-Debug($Message) {}\n" +
                                       '\n'.join(bodies) + '\nif (-not (Set-PiSkillOwnership)) { exit 1 }; Remove-ImpeccableResources\n')
                    command = [PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture)]
                else:
                    fixture = self.root / 'blocked.sh'
                    fixture.write_text('set -eu\nPI_PROFILE_MUTATIONS_BLOCKED=1\n'
                                       'print_warning() { :; }; print_success() { :; }; print_debug() { :; };\n' +
                                       '\n'.join(bodies) + '\nconfigure_pi_skill_ownership\nremove_impeccable_resources\n')
                    command = ['bash', str(fixture)]
                result = subprocess.run(command, env=self.env, capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(settings.read_text(), 'malformed PRIVATE-SENTINEL')
                self.assertEqual((pi_skill / 'SKILL.md').read_text(), 'PRIVATE-SENTINEL')
                self.assertFalse(shared_skill.exists())

    @unittest.skipIf(os.name == 'nt', 'Cross-platform extracted guards with a POSIX preflight-failure fixture')
    def test_real_mixed_cleanup_guards_preserve_both_profiles_and_continue_unrelated_work(self):
        # No setup is sourced. All cleanup/dependency functions below are extracted
        # verbatim. Only logging and the Windows registry PATH boundary are inert.
        rtk = '''## RTK token-optimized commands

- RTK (`rtk-ai/rtk`) is installed by the machine setup scripts when available. Prefer `rtk <command>` for noisy shell commands with supported filters (`git`, `gh`, tests, build/lint tools, package managers, file/search commands) unless full raw output is required.
- Bypass RTK for one command with `RTK_DISABLED=1 <command>` or by running the raw command directly when exact output formatting matters.
'''
        for script in SCRIPTS:
            windows = script == 'win.ps1'
            if windows and not PWSH:
                continue
            kinds = ('rtk', 'attention', 'matt', 'compound') + (() if windows else ('matt-obsolete',))
            for kind in kinds:
                with self.subTest(script=script, kind=kind):
                    case = self.root / (script + '-' + kind)
                    home = case / 'home'
                    home.mkdir(parents=True, mode=0o700)
                    case.chmod(0o700)
                    default = home / '.pi/agent'
                    custom = home / 'custom-parent/active'
                    def put(file, text='PRIVATE-SENTINEL'):
                        file.parent.mkdir(parents=True, exist_ok=True)
                        file.write_text(text)
                    for profile in (default, custom):
                        put(profile / 'AGENTS.md', '# PRIVATE-SENTINEL\n\n' + rtk + '\n')
                        put(profile / 'APPEND_SYSTEM.md', 'PRIVATE-SENTINEL\n<!-- attention-span:start -->\nmanaged\n<!-- attention-span:end -->\n')
                        put(profile / 'settings.json', '{"keep":"PRIVATE-SENTINEL"}')
                        for skill in ('diagnosing-bugs', 'diagnose', 'lfg'):
                            put(profile / 'skills' / skill / 'SKILL.md')
                    custom.parent.chmod(0o777)  # Reject the whole two-profile transaction.
                    env = {**self.env, 'HOME': str(home), 'USERPROFILE': str(home),
                           'PI_CODING_AGENT_DIR': str(custom), 'LOCALAPPDATA': str(home / 'local'),
                           'APPDATA': str(home / 'roaming')}
                    program = case / 'prepare.cjs'
                    program.write_text(embedded(script))
                    preflight = subprocess.run([NODE, str(program), str(home), str(custom)], env=env,
                                               text=True, capture_output=True, timeout=30)
                    self.assertNotEqual(preflight.returncode, 0)
                    self.assertIn('unsafe-ancestor', preflight.stdout)
                    if kind == 'rtk':
                        artifact = home / '.claude/RTK.md'
                        target = 'Remove-RtkResources' if windows else 'remove_rtk_resources'
                        select = (lambda n: 'Rtk' in n) if windows else (lambda n: n.startswith('rtk_') or n == target)
                    elif kind == 'attention':
                        artifact = home / '.claude/output-styles/attention-kind.md'
                        target = 'Remove-AttentionSpanResources' if windows else 'remove_attention_span_resources'
                        select = (lambda n: 'AttentionSpan' in n) if windows else (lambda n: n.startswith('attention_span_') or n == target)
                    elif kind.startswith('matt'):
                        artifact = home / '.agents/skills' / ('diagnose' if kind == 'matt-obsolete' else 'diagnosing-bugs') / 'SKILL.md'
                        target = 'Remove-MattPocockSkills' if windows else ('remove_obsolete_matt_pocock_skills' if kind == 'matt-obsolete' else 'remove_matt_pocock_skills')
                        select = (lambda n: 'MattPocock' in n and not n.startswith('Setup-')) if windows else (lambda n: n.startswith('matt_pocock_') or n == target)
                    else:
                        artifact = home / '.agents/skills/lfg'
                        target = 'Remove-CompoundEngineeringResources' if windows else 'remove_compound_engineering_resources'
                        select = (lambda n: 'Compound' in n or n in ('Test-PathWithin', 'Test-SafeProfileDirectory')) if windows else (lambda n: n.startswith('compound_') or n in (target, 'remove_pi_compound_settings'))
                    bodies = extracted_functions(script, select)
                    def snapshot(profile):
                        return {str(p.relative_to(profile)): p.read_bytes() for p in profile.rglob('*') if p.is_file()}
                    before = [snapshot(profile) for profile in (default, custom)]
                    for blocked in (True, False):
                        # The unblocked control must modify each profile; otherwise
                        # a no-op cleanup fixture could falsely prove a safety gate.
                        if kind == 'compound':
                            repo = home / '.local/share/compound-engineering-plugin/skills/lfg'
                            put(repo / 'SKILL.md')
                            artifact.parent.mkdir(parents=True, exist_ok=True)
                            artifact.symlink_to(repo, target_is_directory=True)
                        else:
                            put(artifact)
                        if windows:
                            fixture = case / 'guard.ps1'
                            code = "$ErrorActionPreference='Stop'\n$script:PiProfileMutationsBlocked=$" + str(blocked).lower() + '\n'
                            code += "function Write-Warning($Message) {}\nfunction Write-Success($Message) {}\nfunction Write-Debug($Message) {}\n"
                            code += bodies + '\nfunction Remove-RtkPathEntry { } # Registry writes are outside this fixture.\n'
                            code += target + '\n'
                            command = [PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture)]
                        else:
                            fixture = case / 'guard.sh'
                            code = 'set -eu\nPI_PROFILE_MUTATIONS_BLOCKED=' + ('1' if blocked else '0') + '\n'
                            code += 'print_error() { :; }; print_warning() { :; }; print_success() { :; }; print_debug() { :; };\n'
                            code += bodies + '\n' + target + '\n'
                            command = ['bash', str(fixture)]
                        fixture.write_text(code)
                        result = subprocess.run(command, env=env, cwd=case, text=True, capture_output=True, timeout=30)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertFalse(artifact.exists() or artifact.is_symlink(), 'Unrelated managed cleanup must continue')
                        for profile, prior in zip((default, custom), before):
                            if blocked:
                                self.assertEqual(snapshot(profile), prior)
                            else:
                                self.assertNotEqual(snapshot(profile), prior, 'Control must exercise real Pi cleanup')

    @unittest.skipUnless(PWSH, 'Set PWSH_BIN for native-script parsing and C# compilation')
    def test_native_acl_program_parses_and_compiles_without_calling_windows_apis(self):
        import re
        code = embedded('win.ps1')
        native = re.search(r'const script = String.raw`(.*?)`;', code, re.S)[1]
        csharp = re.search(r'Add-Type -TypeDefinition @"\n(.*?)\n"@', native, re.S)[1]
        native_path = self.root / 'native.ps1'
        native_path.write_text(native)
        fixture = self.root / 'compile.ps1'
        fixture.write_text("$ErrorActionPreference='Stop'\n"
                           "$errors=$null; $tokens=$null\n"
                           "$null=[System.Management.Automation.Language.Parser]::ParseFile($args[0], [ref]$tokens, [ref]$errors)\n"
                           "if ($errors.Count) { throw 'native parser failed' }\n"
                           "Add-Type -TypeDefinition @'\n" + csharp + "\n'@\n")
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture), str(native_path)],
                                env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(os.name == 'nt' and PWSH, 'Native Windows ACLs require Windows, not portable Linux PowerShell')
    def test_native_windows_private_acls_do_not_propagate_into_credentials_or_dependencies(self):
        self.create_profile()
        child = self.profile / 'npm/node_modules/fixture'
        child.mkdir(parents=True)
        auth = self.profile / 'auth.json'
        auth.write_text('PRIVATE-SENTINEL')
        fixture = self.root / 'acls.ps1'
        fixture.write_text(r'''param($Action, $HomePath)
$ErrorActionPreference='Stop'
$pi=Join-Path $HomePath '.pi'
$profile=Join-Path $pi 'agent'
if ($Action -eq 'seed') {
    foreach ($file in @($pi,$profile)) {
        $acl=Get-Acl -LiteralPath $file
        $rule=[System.Security.AccessControl.FileSystemAccessRule]::new(
            [System.Security.Principal.SecurityIdentifier]::new('S-1-1-0'), 'ReadAndExecute',
            'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $file -AclObject $acl
    }
} elseif ($Action -eq 'private') {
    $allowed=@([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')
    foreach ($file in @($pi,$profile)) {
        $acl=Get-Acl -LiteralPath $file
        if (-not $acl.AreAccessRulesProtected) { throw 'not protected' }
        foreach ($rule in $acl.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier])) {
            if ($rule.IdentityReference.Value -notin $allowed) { throw 'not private' }
        }
    }
}
@((Get-Acl -LiteralPath $HomePath).Sddl,
  (Get-Acl -LiteralPath (Join-Path $profile 'auth.json')).Sddl,
  (Get-Acl -LiteralPath (Join-Path $profile 'npm/node_modules/fixture')).Sddl) | ConvertTo-Json -Compress
''')
        def acl(action):
            result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture), action, str(self.home)],
                                    env=self.env, text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return result.stdout
        before = acl('seed')
        for _ in range(2):
            result = self.helper(script='win.ps1')
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(acl('private'), before)
            self.assertEqual(auth.read_text(), 'PRIVATE-SENTINEL')

    @unittest.skipUnless(os.name == 'nt' and PWSH, 'Native Windows handle races require Windows, not Linux PowerShell')
    def test_native_windows_substitution_reparse_and_parent_disappearance_fail_closed(self):
        import re
        native = re.search(r'const script = String.raw`(.*?)`;', embedded('win.ps1'), re.S)[1]
        csharp = re.search(r'Add-Type -TypeDefinition @"\n(.*?)\n"@', native, re.S)[1]
        fixture = self.root / 'native-races.ps1'
        fixture.write_text("param($HomePath)\n$ErrorActionPreference='Stop'\nAdd-Type -TypeDefinition @'\n" + csharp + "\n'@\n" + r'''
$owner=[System.Security.Principal.WindowsIdentity]::GetCurrent().User
$private=[System.Security.AccessControl.DirectorySecurity]::new()
$private.SetOwner($owner)
$private.SetAccessRuleProtection($true,$false)
$private.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($owner,'FullControl','Allow'))
$parent=Join-Path $HomePath 'parent'
$old=Join-Path $HomePath 'moved'
$outside=Join-Path $HomePath 'outside'
$null=New-Item -ItemType Directory -Path $parent,$outside
$pin=[PiDirectoryAcl]::Pin($parent,$true,$true,$false)
try {
    $denied=$false
    try { Move-Item -LiteralPath $parent -Destination $old -ErrorAction Stop } catch { $denied=$true }
    if (-not $denied) { throw 'Pinned parent renamed' }
    $denied=$false
    try { Remove-Item -LiteralPath $parent -ErrorAction Stop } catch { $denied=$true }
    if (-not $denied) { throw 'Pinned parent removed' }
    $leaf=[PiDirectoryAcl]::CreateLeaf($pin,'agent',$private.GetSecurityDescriptorBinaryForm(),$false)
    $leaf.Dispose()
    if (-not (Test-Path -LiteralPath (Join-Path $parent 'agent'))) { throw 'Rooted leaf missing' }
    if ((Get-ChildItem -LiteralPath $outside).Count) { throw 'Outside changed' }
    $identity=[PiDirectoryAcl]::Identity($pin)
    $created=[IO.Directory]::GetCreationTimeUtc($parent)
} finally { $pin.Dispose() }
Move-Item -LiteralPath $parent -Destination $old
$null=New-Item -ItemType Directory -Path $parent
[IO.Directory]::SetCreationTimeUtc($parent,$created)
$before=(Get-Acl -LiteralPath $parent).Sddl
$substitute=[PiDirectoryAcl]::Pin($parent,$true,$true,$false)
try {
    $denied=$false
    try { [PiDirectoryAcl]::Secure($substitute,$identity,$owner.Value,$private.GetSecurityDescriptorBinaryForm()) }
    catch { $denied=$true }
    if (-not $denied) { throw 'Same-time substitution accepted' }
    if ((Get-Acl -LiteralPath $parent).Sddl -ne $before) { throw 'Substitute ACL changed' }
} finally { $substitute.Dispose() }
Remove-Item -LiteralPath $parent
$denied=$false
try { $unexpected=[PiDirectoryAcl]::CreateLeaf($substitute,'unexpected',$private.GetSecurityDescriptorBinaryForm(),$false) }
catch { $denied=$true }
if (-not $denied -or (Test-Path -LiteralPath $parent)) { throw 'Disappeared parent recreated' }
$null=New-Item -ItemType Junction -Path $parent -Target $outside
$denied=$false
try { $unexpected=[PiDirectoryAcl]::Pin($parent,$true,$true,$false) } catch { $denied=$true }
if (-not $denied) { $unexpected.Dispose(); throw 'Reparse point accepted' }
if ((Get-ChildItem -LiteralPath $outside).Count) { throw 'Outside changed through reparse point' }
''')
        result = subprocess.run([PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture), str(self.home)],
                                env=self.env, text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_extracted_wrappers_prepare_or_fail_closed_without_native_error_leaks(self):
        for script in SCRIPTS:
            if script == 'win.ps1' and not PWSH:
                continue
            with self.subTest(script=script):
                text = (ROOT / script).read_text()
                signature = 'function Prepare-PiProfilePermissions {' if script == 'win.ps1' else 'prepare_pi_profile_permissions() {'
                start = text.index(signature)
                body = text[start:text.index('\n}\n', text.index(END, start)) + 2]
                for outcome in ('success', 'runtime-failure', 'unknown-output', 'linked-profile'):
                    link = self.home / 'linked'
                    if not link.exists():
                        link.symlink_to(self.root, target_is_directory=True)
                    env = {**self.env, 'PI_CODING_AGENT_DIR': str(link) if outcome == 'linked-profile' else '',
                           'NODE_OPTIONS': '--PRIVATE-SENTINEL', 'NODE_PATH': 'PRIVATE-SENTINEL'}
                    if script == 'win.ps1':
                        fixture = self.root / 'wrapper.ps1'
                        fixture.write_text("$ErrorActionPreference='Stop'\n$PSNativeCommandUseErrorActionPreference=$true\n"
                                           "function Write-Warning($Message) { [Console]::WriteLine($Message) }\n"
                                           "function Write-Debug($Message) { [Console]::WriteLine($Message) }\n"
                                           'function Enable-SharedNodeRuntime { return $' + ('false' if outcome == 'runtime-failure' else 'true') + ' }\n' +
                                           ("function node { Write-Output 'PRIVATE-SENTINEL'; $global:LASTEXITCODE=1 }\n" if outcome == 'unknown-output' else '') +
                                           body + "\n$ok=Prepare-PiProfilePermissions\n"
                                           "if ($env:NODE_OPTIONS -ne '--PRIVATE-SENTINEL' -or $env:NODE_PATH -ne 'PRIVATE-SENTINEL' -or -not $PSNativeCommandUseErrorActionPreference) { throw 'environment changed' }\n"
                                           "if (-not $ok) { exit 1 }\n")
                        command = [PWSH, '-NoProfile', '-NonInteractive', '-File', str(fixture)]
                    else:
                        fixture = self.root / 'wrapper.sh'
                        prefix = "set -eu\nprint_warning() { printf '%s\\n' \"$1\"; }; print_debug() { :; };\n"
                        prefix += 'ensure_shared_node_runtime() { return ' + ('1' if outcome == 'runtime-failure' else '0') + '; }\n'
                        if outcome == 'unknown-output':
                            binary = self.root / 'bin/node'
                            binary.parent.mkdir(exist_ok=True)
                            binary.write_text("#!/bin/sh\nprintf 'PRIVATE-SENTINEL\\n'\nexit 1\n")
                            binary.chmod(0o755)
                            env['PATH'] = str(binary.parent) + os.pathsep + env['PATH']
                        fixture.write_text(prefix + body + '\nprepare_pi_profile_permissions\n')
                        command = ['bash', str(fixture)]
                    result = subprocess.run(command, env=env, cwd=self.root, text=True, capture_output=True, timeout=30)
                    self.assertNotIn('PRIVATE-SENTINEL', result.stdout + result.stderr)
                    self.assertEqual(result.returncode == 0, outcome == 'success', result.stdout + result.stderr)

    @unittest.skipIf(os.name == 'nt', 'Linux system home alias fixture')
    def test_only_the_trusted_system_home_alias_is_accepted(self):
        import json
        system = self.root / 'system'
        real_home = system / 'var/home/fixture-user'
        real_home.mkdir(parents=True)
        for directory in (system, system / 'var', system / 'var/home', real_home):
            directory.chmod(0o755)
        (system / 'home').symlink_to('var/home', target_is_directory=True)
        prelude = "const fixtureFs = require('node:fs'), fixturePath = require('node:path');\n"
        prelude += 'const fixtureSystem = ' + json.dumps(str(system)) + ';\n'
        prelude += r'''
const fixtureMap = file => ['/home', '/var', '/var/home'].includes(file) || file.startsWith('/home/') ? fixtureSystem + file : file;
for (const name of ['lstatSync', 'readlinkSync', 'realpathSync']) {
    const original = fixtureFs[name];
    fixtureFs[name] = (file, ...args) => {
        const value = original(fixtureMap(file), ...args);
        if (name === 'lstatSync' && ['/home', '/var', '/var/home'].includes(file)) value.uid = 0;
        return value;
    };
}
process.argv[2] = '/home/fixture-user';
process.argv[3] = '/home/fixture-user/active';
'''
        result = self.helper(prelude=prelude)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((real_home / 'active').stat().st_mode & 0o777, 0o700)
        (system / 'var').chmod(0o777)
        result = self.helper(prelude=prelude)
        self.assertNotEqual(result.returncode, 0)
        (system / 'var').chmod(0o755)
        (system / 'home').unlink()
        (system / 'home').symlink_to(str(system / 'var/home'), target_is_directory=True)
        result = self.helper(prelude=prelude)
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
