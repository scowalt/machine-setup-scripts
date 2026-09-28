#!/usr/bin/env python3
"""Embed the reviewed OpenCode policy so curl|bash entry points stay standalone.

Version 1 | Last changed: Generate identical standalone OpenCode policy blocks
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
START = '# BEGIN GENERATED OPENCODE CLI\n'
END = '# END GENERATED OPENCODE CLI'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    core = (ROOT / 'lib/opencode-cli.cjs').read_text().rstrip()
    for name in ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1'):
        source = ROOT / name
        text = source.read_text()
        wrapper = ROOT / ('lib/opencode-cli.ps1' if name.endswith('.ps1') else 'lib/opencode-cli.bash')
        block = wrapper.read_text().replace('// @OPENCODE_CORE@', core)
        assert text.count(START) == text.count(END) == 1, name
        before, remainder = text.split(START)
        _, after = remainder.split(END)
        expected = before + START + block + END + after
        if args.check:
            assert text == expected, f'{name}: run python3 tools/embed-opencode-cli.py'
        else:
            source.write_text(expected)


if __name__ == '__main__':
    main()
