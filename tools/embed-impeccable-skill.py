#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ('mac.sh', 'ubuntu.sh', 'wsl.sh', 'pi.sh', 'bazzite.sh', 'win.ps1')


def render(root, shell):
    suffix = 'ps1' if shell == 'powershell' else 'bash'
    core = (root / 'lib/impeccable-skill.cjs').read_text().rstrip()
    wrapper = (root / ('lib/impeccable-skill.' + suffix)).read_text().rstrip()
    if wrapper.count('@IMPECCABLE_CORE@') != 1:
        raise ValueError('Impeccable core placeholder must occur exactly once')
    match = re.search(r'const impeccableReasons = (\[[\s\S]*?\]);', core)
    if not match:
        raise ValueError('Missing Impeccable diagnostic allowlist')
    reasons = json.loads(match[1])
    if not reasons or any(not re.fullmatch(r'[A-Za-z][A-Za-z0-9-]*', reason) for reason in reasons):
        raise ValueError('Invalid Impeccable diagnostic allowlist')
    selection = ','.join("'" + reason + "'" for reason in reasons) if suffix == 'ps1' else '|'.join(reasons)
    wrapper = wrapper.replace('@IMPECCABLE_REASONS@', selection)
    marker = "$null = '" if suffix == 'ps1' else ": '"
    return (marker + "BEGIN_GENERATED_IMPECCABLE_SKILL'\n" + wrapper.replace('@IMPECCABLE_CORE@', core)
            + '\n' + marker + "END_GENERATED_IMPECCABLE_SKILL'\n")


def embed(root, check):
    updates = []
    for name in SCRIPTS:
        source = root / name
        text = source.read_text()
        shell = 'powershell' if name.endswith('.ps1') else 'bash'
        block = render(root, shell)
        marker = "$null = '" if shell == 'powershell' else ": '"
        begin, end = marker + "BEGIN_GENERATED_IMPECCABLE_SKILL'", marker + "END_GENERATED_IMPECCABLE_SKILL'"
        if text.count(begin) != text.count(end) or text.count(begin) > 1:
            raise ValueError(name + ': invalid Impeccable embedding boundary')
        if begin in text:
            first = text.index(begin)
            last = text.index(end, first) + len(end)
            if text[last:last + 1] == '\n':
                last += 1
            updated = text[:first] + block + text[last:]
        else:
            anchor = 'function Install-ManagedAgentSkill {' if shell == 'powershell' else 'install_managed_agent_skill() {'
            if text.count(anchor) != 1:
                raise ValueError(name + ': missing unique Impeccable insertion anchor')
            first = text.index(anchor)
            updated = text[:first] + block + '\n' + text[first:]
        if updated != text:
            updates.append((source, updated))
    if check and updates:
        raise ValueError('Stale Impeccable embeddings: ' + ', '.join(source.name for source, _ in updates))
    if not check:
        for source, updated in updates:
            source.write_text(updated)


def main():
    parser = argparse.ArgumentParser(description='Version 2 | Embed synchronized Impeccable policy and diagnostic allowlists; callers/version banners are maintained separately.')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--render', choices=('bash', 'powershell'))
    args = parser.parse_args()
    try:
        if args.render:
            print(render(args.root, args.render), end='')
        else:
            embed(args.root, args.check)
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
