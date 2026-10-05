#!/usr/bin/env python3
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parents[1]
BASH = ('mac.sh', 'ubuntu.sh', 'pi.sh', 'bazzite.sh', 'wsl.sh')


def embed(check=False):
    stale = []
    for name in (*BASH, 'win.ps1'):
        target = ROOT / name
        text = target.read_text()
        is_ps = name.endswith('.ps1')
        policy = (ROOT / 'lib' / ('setup-policy.ps1' if is_ps else 'setup-policy.bash')).read_text().rstrip()
        marker = "$null = '" if is_ps else ": '"
        begin = marker + "BEGIN_SETUP_ENVIRONMENT_POLICY'"
        end = marker + "END_SETUP_ENVIRONMENT_POLICY'"
        block = begin + '\n' + policy + '\n' + end
        if begin in text:
            first = text.index(begin)
            last = text.index(end, first) + len(end)
            updated = text[:first] + block + text[last:]
        else:
            marker = "$null = 'BEGIN_SETUP_ENVIRONMENT_FILE'" if is_ps else 'SETUP_ORIGINAL_PATH='
            index = text.index(marker)
            updated = text[:index] + block + '\n\n' + text[index:]
        if updated != text:
            stale.append(name)
            if not check:
                target.write_text(updated)
    if check and stale:
        raise SystemExit('Stale setup environment policy: ' + ', '.join(stale))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    embed(parser.parse_args().check)
