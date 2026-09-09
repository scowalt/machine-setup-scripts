"""The native fixture must ignore Git variables inherited from the caller or a hook."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get('PASEO_TEST_PLUGIN_SERVICE_MODULE'), 'native Paseo module is not supplied')
@unittest.skipIf(os.name == 'nt', 'native CLI fixture uses POSIX executables')
class NativeFixtureIsolationTest(unittest.TestCase):
    def test_hook_repository_and_index_are_untouched(self):
        # Even this outer trap repository is initialized without the real hook environment.
        clean = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
        clean.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1', GIT_ALLOW_PROTOCOL='file')
        git = shutil.which('git')
        node = shutil.which('node')
        with tempfile.TemporaryDirectory(prefix='paseo-git-isolation-') as temporary:
            foreign = Path(temporary) / 'caller'
            foreign.mkdir()
            def run_git(*args):
                return subprocess.run([git, '-c', 'core.hooksPath=' + os.devnull,
                                       '-c', 'user.name=Caller Fixture', '-c', 'user.email=caller@example.test',
                                       '-c', 'commit.gpgsign=false', *args], cwd=foreign, env=clean,
                                      check=True, capture_output=True, timeout=10)
            run_git('init', '-b', 'main')
            (foreign / 'keep.txt').write_text('keep caller files and repository metadata unchanged')
            run_git('add', '.')
            run_git('commit', '-m', 'caller baseline')
            def snapshot():
                return {str(file.relative_to(foreign)): hashlib.sha256(file.read_bytes()).hexdigest()
                        for file in foreign.rglob('*') if file.is_file()}
            before = snapshot()
            for extra in ({}, {'GIT_WORK_TREE': str(foreign), 'GIT_INDEX_FILE': str(foreign / '.git/index'),
                               'GIT_COMMON_DIR': str(foreign / '.git'), 'GIT_OBJECT_DIRECTORY': str(foreign / '.git/objects')}):
                with self.subTest(extra=tuple(extra)):
                    env = {**clean, 'GIT_DIR': str(foreign / '.git'), **extra}
                    result = subprocess.run([node, str(ROOT / 'tests/paseo-plain-native-migration.mjs')],
                                            cwd=ROOT, env=env, text=True, capture_output=True, timeout=60)
                    self.assertEqual(snapshot(), before, 'Native fixture mutated the caller repository or files')
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
