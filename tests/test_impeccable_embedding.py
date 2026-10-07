from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ['mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1']


class ImpeccableEmbedding(unittest.TestCase):
    def test_generator_renders_both_adapters_and_idempotently_embeds_all_six_standalone_scripts(self):
        with tempfile.TemporaryDirectory(prefix='impeccable-embedding-') as temporary:
            root = Path(temporary)
            (root / 'lib').mkdir()
            for source in (ROOT / 'lib').glob('impeccable-skill.*'):
                shutil.copy2(source, root / 'lib' / source.name)
            for name in SCRIPTS:
                (root / name).write_text('function Install-ManagedAgentSkill {\n}\n' if name.endswith('.ps1') else 'install_managed_agent_skill() {\n    :\n}\n')
            command = ['/usr/bin/python3', '-I', str(ROOT / 'tools/embed-impeccable-skill.py'), '--root', str(root)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            before = {name: (root / name).read_bytes() for name in SCRIPTS}
            subprocess.run(command, check=True, capture_output=True, timeout=15)
            result = subprocess.run(command + ['--check'], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            for name in SCRIPTS:
                self.assertEqual((root / name).read_bytes(), before[name])
                self.assertNotIn('@IMPECCABLE_CORE@', (root / name).read_text())
            for shell, name in [('bash', 'mac.sh'), ('powershell', 'win.ps1')]:
                rendered = subprocess.run(command + ['--render', shell], check=True, capture_output=True, text=True, timeout=15).stdout
                self.assertIn(rendered.rstrip(), (root / name).read_text())
            script = root / 'mac.sh'
            script.write_text(script.read_text().replace('Impeccable: installer-failed.', 'outdated fixture diagnostic'))
            result = subprocess.run(command + ['--check'], capture_output=True, text=True, timeout=15)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('mac.sh', result.stderr)


if __name__ == '__main__':
    unittest.main()
