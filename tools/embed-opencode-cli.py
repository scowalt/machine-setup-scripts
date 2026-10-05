#!/usr/bin/env python3
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
START = "BEGIN_GENERATED_OPENCODE_CLI'\n"
END = "END_GENERATED_OPENCODE_CLI'"


def main():
    parser = argparse.ArgumentParser(description='Embed the reviewed OpenCode policy so curl|bash entry points stay standalone.\n\nVersion 1 | Last changed: Generate identical standalone OpenCode policy blocks\n')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    core = (ROOT / 'lib/opencode-cli.cjs').read_text().rstrip()
    for name in ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1'):
        source = ROOT / name
        text = source.read_text()
        wrapper = ROOT / ('lib/opencode-cli.ps1' if name.endswith('.ps1') else 'lib/opencode-cli.bash')
        block = wrapper.read_text().replace('// @OPENCODE_CORE@', core)
        marker = "$null = '" if name.endswith('.ps1') else ": '"
        start, end = marker + START, marker + END
        assert text.count(start) == text.count(end) == 1, name
        before, remainder = text.split(start)
        _, after = remainder.split(end)
        expected = before + start + block + end + after
        if args.check:
            assert text == expected, f'{name}: run python3 tools/embed-opencode-cli.py'
        else:
            source.write_text(expected)


if __name__ == '__main__':
    main()
