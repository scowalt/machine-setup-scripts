"""Inert skills CLI fixture. Only called with test-owned HOME and explicit paths."""
import json
import os
from pathlib import Path
import sys

EXPECTED = [
    '--yes', 'skills@latest', 'add', 'mattpocock/skills', '--global',
    '--agent', 'claude-code', '--agent', 'codex', '--agent', 'gemini-cli',
    '--skill', '*', '--full-depth', '--copy', '--yes', '--json',
]
arguments = json.loads(os.environ['SKILL_TEST_ARGS']) if os.environ.get('SKILL_TEST_ARGS') else sys.argv[1:]
if arguments != EXPECTED:
    print('Unexpected fixture arguments: ' + json.dumps(arguments), file=sys.stderr)
    sys.exit(90)
home = Path(os.environ['SKILL_TEST_HOME'])
assert str(home) == os.environ['USERPROFILE'] == os.environ['HOME']
assert (home / '.test-owned').is_file()
with Path(os.environ['SKILL_TEST_CALLS']).open('a') as calls:
    calls.write(json.dumps(arguments) + '\n')
mode = os.environ.get('SKILL_TEST_MODE', '')
if mode == 'failed-command':
    print('PRIVATE-SENTINEL simulated arbitrary command output', file=sys.stderr)
    sys.exit(1)
skills = json.loads((Path(__file__).parent / 'fixtures/matt-pocock-skills.json').read_text())['skills']
skills += ['new-upstream-skill']
claude = Path(os.environ.get('CLAUDE_CONFIG_DIR') or home / '.claude')
roots = [claude / 'skills', home / '.agents/skills']
lock_file = Path(os.environ['XDG_STATE_HOME']) / 'skills/.skill-lock.json' if os.environ.get('XDG_STATE_HOME') else home / '.agents/.skill-lock.json'
lock = json.loads(lock_file.read_text()) if lock_file.exists() else {'version': 3, 'skills': {}}
report = []
for skill in skills:
    for root in roots:
        dest = root / skill
        dest.mkdir(parents=True, exist_ok=True)
        (dest / 'SKILL.md').write_text(f'---\nname: {skill}\ndescription: Inert test skill.\n---\nFixture only.\n')
        (dest / 'references').mkdir(exist_ok=True)
        (dest / 'references/guide.md').write_text('Upstream fixture: do not execute.\n')
    lock['skills'][skill] = {'source': 'mattpocock/skills', 'sourceType': 'github', 'sourceUrl': 'https://github.com/mattpocock/skills.git'}
    report.append({'name': skill, 'status': 'installed', 'source': 'mattpocock/skills', 'scope': 'global', 'mode': 'copy', 'agents': ['Claude Code', 'Codex', 'Gemini CLI']})
lock_file.parent.mkdir(parents=True, exist_ok=True)
lock_file.write_text(json.dumps(lock))
if mode in ('missing-file', 'empty-file', 'linked-file', 'linked-references', 'directory-file'):
    dest = roots[int(os.environ.get('SKILL_TEST_COPY', '0'))] / 'new-upstream-skill'
    artifact = dest / ('references' if mode == 'linked-references' else 'SKILL.md')
    if mode == 'linked-references':
        (artifact / 'guide.md').unlink()
        artifact.rmdir()
    else:
        artifact.unlink()
    if mode == 'empty-file':
        artifact.write_text('')
    elif mode == 'directory-file':
        artifact.mkdir()
    elif mode.startswith('linked-'):
        artifact.symlink_to(home / 'sentinel', target_is_directory=(mode == 'linked-references'))
if mode == 'partial-report':
    report.pop(0)
if mode == 'failed-result':
    report[0]['status'] = 'failed'
if mode == 'skipped-result':
    report[0]['status'] = 'skipped'
if mode == 'missing-agent':
    report[0]['agents'].remove('Claude Code')
if mode == 'wrong-source':
    report[0]['source'] = 'another/repo'
if mode == 'duplicate-name':
    report.append(report[0])
if mode == 'unsafe-name':
    report[0]['name'] = '../sentinel'
print('PRIVATE-SENTINEL malformed output' if mode == 'invalid-json' else json.dumps(report))
