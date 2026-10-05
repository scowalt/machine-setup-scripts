#!/usr/bin/env python3
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'pi.sh', 'bazzite.sh', 'wsl.sh')


def embed(check=False):
    policy = (ROOT / 'lib/bb-plugin-refresh.py').read_text().rstrip()
    wrapper = (ROOT / 'lib/bb-plugin-refresh.bash').read_text().rstrip()
    begin, end = ": 'BEGIN_BB_PLUGIN_REFRESH'", ": 'END_BB_PLUGIN_REFRESH'"
    block = begin + '\n' + wrapper.replace('@@PYTHON@@', policy) + '\n' + end
    stale = []
    for name in SCRIPTS:
        target = ROOT / name
        text = target.read_text()
        if begin in text:
            first = text.index(begin)
            last = text.index(end, first) + len(end)
        else:
            first = last = text.index(": 'BEGIN_BB_MACHINE_PREPARATION'")
            block_for_insert = block + '\n\n'
        updated = text[:first] + (block if begin in text else block_for_insert) + text[last:]
        if updated != text:
            stale.append(name)
            if not check:
                target.write_text(updated)
    if check and stale:
        raise SystemExit('Stale BB plugin refresh: ' + ', '.join(stale))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    embed(parser.parse_args().check)
