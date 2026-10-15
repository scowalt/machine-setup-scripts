#!/usr/bin/env python3
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1')


def render(root, powershell):
    core = (root / 'lib/pi-visual-explainer.cjs').read_text().rstrip()
    wrapper = (root / ('lib/pi-visual-explainer.ps1' if powershell else 'lib/pi-visual-explainer.bash')).read_text().rstrip()
    if wrapper.count('@PI_VISUAL_EXPLAINER_CORE@') != 1:
        raise ValueError('Expected one Visual Explainer core placeholder')
    marker = "$null = '" if powershell else ": '"
    return (marker + "BEGIN_GENERATED_PI_VISUAL_EXPLAINER'\n" + wrapper.replace('@PI_VISUAL_EXPLAINER_CORE@', core)
            + '\n' + marker + "END_GENERATED_PI_VISUAL_EXPLAINER'\n")


def embed(root, check):
    updates = []
    for name in SCRIPTS:
        source = root / name
        text = source.read_text()
        powershell = name.endswith('.ps1')
        marker = "$null = '" if powershell else ": '"
        begin, end = marker + "BEGIN_GENERATED_PI_VISUAL_EXPLAINER'", marker + "END_GENERATED_PI_VISUAL_EXPLAINER'"
        if text.count(begin) != text.count(end) or text.count(begin) > 1:
            raise ValueError(name + ': invalid Visual Explainer embedding boundary')
        if begin in text:
            first = text.index(begin)
            last = text.index(end, first) + len(end)
            if text[last:last + 1] == '\n':
                last += 1
        else:
            anchor = 'function Setup-PiCompanionPackages {' if powershell else 'setup_pi_companion_packages() {'
            if text.count(anchor) != 1:
                raise ValueError(name + ': missing unique Visual Explainer insertion anchor')
            first = last = text.index(anchor)
        updated = text[:first] + render(root, powershell) + text[last:]
        if updated != text:
            updates.append((source, updated))
    if check and updates:
        raise ValueError('Stale Visual Explainer embeddings: ' + ', '.join(source.name for source, _ in updates))
    if not check:
        for source, updated in updates:
            source.write_text(updated)


def main():
    parser = argparse.ArgumentParser(description='Version 1 | Embed native Visual Explainer Pi package policy; maintain callers and banners separately.')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--root', type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        embed(args.root, args.check)
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
