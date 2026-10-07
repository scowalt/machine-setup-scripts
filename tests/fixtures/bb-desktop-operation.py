import os
from pathlib import Path
import subprocess
import sys
import types
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_bb_desktop import DesktopTests, appimage, import_helper_definitions, mac_zip, payload, release


def main():
    entry, platform = sys.argv[1:]
    fixture = DesktopTests()
    fixture.home = Path(os.environ['HOME'])
    fixture.number = os.environ['DESKTOP_FIXTURE_VERSION']
    fixture.calls = []
    fixture.data = mac_zip(fixture.number) if platform == 'macos' else appimage(fixture.number)
    fixture.latest = release(fixture.number, fixture.data, platform)
    fixture.catalogue = [release(n, appimage(n), tag='desktop-v' + n)
                         for n in ('1.0.0', '1.2.3', '2.0.0', '9.0.0')]
    fixture.ns = import_helper_definitions(payload(entry))
    fixture.ns['fetch'] = fixture.fetch
    fixture.ns['command'] = fixture.command
    fixture.ns['running'] = lambda *_: False
    fixture.ns['Path'] = lambda *args: (fixture.home / 'native-system' / Path(*args).relative_to('/')
                                      if args and str(args[0]).startswith('/Applications') else Path(*args))
    if os.environ.get('DESKTOP_FIXTURE_FAILURE') == 'integrity':
        fixture.latest['assets'][0]['digest'] = 'sha256:' + '0' * 64
    chmod = os.chmod
    def no_directory_repair(path, *args, **kwargs):
        if Path(path).is_dir():
            raise AssertionError('directory permission repair forbidden')
        return chmod(path, *args, **kwargs)
    forbidden = AssertionError('native execution or directory privacy proof forbidden')
    with patch.object(fixture.ns['pwd'], 'getpwuid', return_value=types.SimpleNamespace(pw_dir=str(fixture.home))), \
            patch.object(fixture.ns['pwd'], 'getpwall', side_effect=forbidden), \
            patch.object(os, 'getgrouplist', side_effect=forbidden), \
            patch.object(os, 'getxattr', side_effect=forbidden), \
            patch.object(os, 'chown', side_effect=forbidden), \
            patch.object(os, 'chmod', no_directory_repair), \
            patch.object(os, 'confstr', return_value='glibc 2.35'), \
            patch.object(subprocess, 'run', side_effect=forbidden), \
            patch.object(sys, 'argv', ['fixture-operation', platform]):
        return fixture.ns['main']()


if __name__ == '__main__':
    raise SystemExit(main())
