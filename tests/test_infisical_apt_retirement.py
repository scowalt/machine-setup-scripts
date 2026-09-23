"""Offline contract for the embedded APT source retirement helper."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('ubuntu.sh', 'pi.sh', 'wsl.sh')
URL = 'https://dl.cloudsmith.io/public/infisical/infisical-cli/deb/ubuntu'


def helper(script):
    text = (ROOT / script).read_text()
    match = re.search(r"# BEGIN INFISICAL APT SOURCE HELPER\n.*?<<'INFISICAL_APT_PY'\n(.*?)\nINFISICAL_APT_PY", text, re.S)
    if not match:
        raise AssertionError(f'{script}: missing embedded helper')
    return match.group(1)


class Retirement(unittest.TestCase):
    def run_helper(self, root, script='ubuntu.sh'):
        code = helper(script)
        self.assertIn('root = sys.argv[1]', code)
        self.assertTrue(root.is_dir())
        self.assertNotEqual(str(root), '/etc/apt')
        return subprocess.run([sys.executable, '-c', code, str(root)], capture_output=True, text=True)

    def fixture(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name) / 'apt'
        root.mkdir(mode=0o700)
        (root / 'sources.list.d').mkdir(mode=0o700)
        return root

    def test_embedded_helpers_match_across_apt_platforms(self):
        self.assertEqual(helper('ubuntu.sh'), helper('pi.sh'))
        self.assertEqual(helper('ubuntu.sh'), helper('wsl.sh'))

    def test_shared_source_and_repeat_before_mock_update(self):
        root = self.fixture()
        source = root / 'sources.list.d' / 'shared.list'
        other = b'deb https://example.org/repo stable main\n'
        source.write_bytes(other + f'deb [signed-by=/usr/share/keyrings/infisical.gpg] {URL} any-distro any-version\n'.encode())
        source.chmod(0o644)
        for script in SCRIPTS:
            result = self.run_helper(root, script)
            self.assertEqual(result.returncode, 0, result.stderr)
            # The mock update is permitted only after the stale source is gone.
            self.assertEqual(source.read_bytes(), other)
            self.assertEqual(self.run_helper(root, script).returncode, 0)

    def test_deb822_unrelated_stanza_preserved(self):
        root = self.fixture()
        source = root / 'sources.list.d' / 'shared.sources'
        first = f'Types: deb\nURIs: {URL}\nSuites: stable\nComponents: main\n\n'.encode()
        other = b'Types: deb\nURIs: https://example.org/repo\nSuites: stable\nComponents: main\n'
        source.write_bytes(first + other)
        source.chmod(0o644)
        self.assertEqual(self.run_helper(root).returncode, 0)
        self.assertEqual(source.read_bytes(), other)
        self.assertEqual(self.run_helper(root).returncode, 0)

    def test_official_host_lookalike_is_preserved(self):
        root = self.fixture()
        source = root / 'sources.list.d' / 'shared.list'
        other = f'deb https://dl.cloudsmith.io.evil.example/public/infisical/infisical-cli/deb/ubuntu stable main\n'.encode()
        source.write_bytes(other)
        source.chmod(0o644)
        self.assertEqual(self.run_helper(root).returncode, 0)
        self.assertEqual(source.read_bytes(), other)

    def test_folded_mixed_deb822_uris_refused_in_both_orders(self):
        for values in ((f'https://example.org/repo', f' {URL}'),
                       (URL, ' https://example.org/repo'),
                       ('https://example.org/repo', ' https://example.net/repo', f' {URL}')):
            with self.subTest(values=values):
                root = self.fixture()
                source = root / 'sources.list.d' / 'shared.sources'
                data = ('Types: deb\nURIs: ' + values[0] + '\n' + '\n'.join(values[1:]) +
                        '\nSuites: stable\nComponents: main\n').encode()
                source.write_bytes(data)
                source.chmod(0o644)
                self.assertNotEqual(self.run_helper(root).returncode, 0)
                self.assertEqual(source.read_bytes(), data)

    def test_duplicate_uris_field_refused_without_mutation(self):
        for values in ((URL, 'https://example.org/repo'), ('https://example.org/repo', URL)):
            with self.subTest(values=values):
                root = self.fixture()
                source = root / 'sources.list.d' / 'shared.sources'
                data = f'Types: deb\nURIs: {values[0]}\nURIs: {values[1]}\nSuites: stable\n'.encode()
                source.write_bytes(data)
                source.chmod(0o644)
                self.assertNotEqual(self.run_helper(root).returncode, 0)
                self.assertEqual(source.read_bytes(), data)

    def test_unrelated_continuation_does_not_erase_other_stanza(self):
        root = self.fixture()
        source = root / 'sources.list.d' / 'shared.sources'
        other = b'Types: deb\nURIs: https://example.org/repo\nSuites: stable\nComponents: main\nSigned-By:\n some-other-key\n\n'
        managed = f'Types: deb\nURIs: {URL}\nSuites: stable\nComponents: main\n'.encode()
        source.write_bytes(other + managed)
        source.chmod(0o644)
        self.assertEqual(self.run_helper(root).returncode, 0)
        self.assertEqual(source.read_bytes(), other)

    def test_replacement_url_exact_path_and_lookalikes(self):
        for url in ('https://artifacts-cli.infisical.com/deb', 'https://artifacts-cli.infisical.com/deb/'):
            for ext, content in (('list', f'deb {url} stable main\n'),
                                 ('sources', f'Types: deb\nURIs: {url}\nSuites: stable\nComponents: main\n')):
                with self.subTest(url=url, ext=ext):
                    root = self.fixture()
                    source = root / 'sources.list.d' / ('shared.' + ext)
                    unrelated = ('deb https://artifacts-cli.infisical.com/deb-other stable main\n' if ext == 'list'
                                 else 'Types: deb\nURIs: https://artifacts-cli.infisical.com.evil/deb\nSuites: stable\n\n')
                    source.write_text(unrelated + content)
                    source.chmod(0o644)
                    self.assertEqual(self.run_helper(root).returncode, 0)
                    self.assertEqual(source.read_text(), unrelated)

    def test_occupied_temporary_file_never_unlinked(self):
        root = self.fixture()
        source = root / 'sources.list.d' / 'shared.list'
        data = f'deb {URL} stable main\n'.encode()
        source.write_bytes(data)
        source.chmod(0o644)
        code = "import os, sys; from pathlib import Path; root=Path(sys.argv[1]); " \
               "name='.infisical-retirement-%d-shared.list' % os.getpid(); " \
               "occupied=root/'sources.list.d'/name; occupied.write_bytes(b'owned by someone else'); " \
               "occupied.chmod(0o644); exec(sys.argv[2])"
        self.assertIn('root = sys.argv[1]', helper('ubuntu.sh'))
        self.assertNotEqual(str(root), '/etc/apt')
        result = subprocess.run([sys.executable, '-c', code, str(root), helper('ubuntu.sh')], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(source.read_bytes(), data)
        occupied = list((root / 'sources.list.d').glob('.infisical-retirement-*'))
        self.assertEqual(len(occupied), 1)
        self.assertEqual(occupied[0].read_bytes(), b'owned by someone else')

    def test_deb822_shared_stanza_refused_without_changes(self):
        root = self.fixture()
        source = root / 'sources.list.d' / 'shared.sources'
        data = f'Types: deb\nURIs: {URL} https://example.org/repo\nSuites: any-distro\nComponents: main\n'.encode()
        source.write_bytes(data)
        source.chmod(0o644)
        self.assertNotEqual(self.run_helper(root).returncode, 0)
        self.assertEqual(source.read_bytes(), data)

    def test_link_refused(self):
        root = self.fixture()
        outside = root / 'outside'
        outside.write_text(f'deb {URL} any-distro main\n')
        (root / 'sources.list.d' / 'linked.list').symlink_to(outside)
        self.assertNotEqual(self.run_helper(root).returncode, 0)
        self.assertIn(URL, outside.read_text())

    def test_changed_temporary_path_not_unlinked_or_followed(self):
        root = self.fixture()
        source = root / 'sources.list.d' / 'shared.list'
        data = f'deb {URL} stable main\n'.encode()
        source.write_bytes(data)
        source.chmod(0o644)
        outside = root / 'outside'
        outside.write_bytes(b'preserve')
        code = helper('ubuntu.sh')
        anchor = '            temp_now = os.stat(tmp, dir_fd=directory, follow_symlinks=False)'
        self.assertIn(anchor, code)
        injection = ("            os.rename(tmp, tmp + '.owned', src_dir_fd=directory, dst_dir_fd=directory)\n"
                     "            os.symlink('outside', tmp, dir_fd=directory)\n")
        code = code.replace(anchor, injection + anchor, 1)
        result = subprocess.run([sys.executable, '-c', code, str(root)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(source.read_bytes(), data)
        self.assertEqual(outside.read_bytes(), b'preserve')
        temps = list((root / 'sources.list.d').glob('.infisical-retirement-*'))
        self.assertEqual(len(temps), 2)
        self.assertEqual(sum(path.is_symlink() for path in temps), 1)

    def test_xattr_added_between_preflight_and_write_is_preserved(self):
        root = self.fixture()
        source = root / 'sources.list.d' / 'shared.list'
        data = f'deb {URL} stable main\n'.encode()
        source.write_bytes(data)
        source.chmod(0o644)
        try:
            os.setxattr(source, 'user.retirement-fixture', b'probe')
            os.removexattr(source, 'user.retirement-fixture')
        except OSError:
            self.skipTest('test filesystem does not support user xattrs')
        code = helper('ubuntu.sh')
        anchor = '    for directory, name, info, data, updated in changes:'
        self.assertEqual(code.count(anchor), 1)
        code = code.replace(anchor, "    os.setxattr(os.path.join(root, 'sources.list.d', 'shared.list'), 'user.retirement-fixture', b'new')\n" + anchor)
        result = subprocess.run([sys.executable, '-c', code, str(root)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(source.read_bytes(), data)
        self.assertEqual(os.getxattr(source, 'user.retirement-fixture'), b'new')

    def test_extended_metadata_is_not_discarded(self):
        root = self.fixture()
        source = root / 'sources.list.d' / 'shared.list'
        data = f'deb {URL} stable main\n'.encode()
        source.write_bytes(data)
        source.chmod(0o644)
        try:
            os.setxattr(source, 'user.retirement-fixture', b'preserve')
        except OSError:
            self.skipTest('test filesystem does not support user xattrs')
        self.assertNotEqual(self.run_helper(root).returncode, 0)
        self.assertEqual(source.read_bytes(), data)
        self.assertEqual(os.getxattr(source, 'user.retirement-fixture'), b'preserve')

    def test_preflight_prevents_partial_mutation(self):
        root = self.fixture()
        source = root / 'sources.list'
        data = f'deb {URL} any-distro main\n'.encode()
        source.write_bytes(data)
        source.chmod(0o644)
        (root / 'sources.list.d' / 'bad.list').symlink_to(source)
        self.assertNotEqual(self.run_helper(root).returncode, 0)
        self.assertEqual(source.read_bytes(), data)


if __name__ == '__main__':
    unittest.main()
