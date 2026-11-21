#!/usr/bin/python3
import json
import os
import sys

home = os.environ['HOME']
root = os.environ.get('FAKE_BUN_ROOT', os.path.join(home, '.bun'))
global_dir = os.path.join(root, 'install', 'global')
bin_dir = os.path.join(root, 'bin')
manifest = os.path.join(global_dir, 'package.json')
args = sys.argv[1:]
sys.stdout.reconfigure(encoding='utf-8')
with open(os.environ['TEST_CAPTURE'] + '.calls', 'a') as log:
    log.write(' '.join(args) + '\n')


def dependencies():
    try:
        with open(manifest) as handle:
            return json.load(handle).get('dependencies', {})
    except (OSError, ValueError):
        return {}


def fail(message):
    sys.stderr.write(message + '\n')
    sys.exit(1)


removed = os.path.exists(os.environ['TEST_CAPTURE'] + '.removed')
if args == ['pm', 'ls', '-g']:
    if os.environ.get('TEST_LS_FAILS') == '1' or (removed and os.environ.get('TEST_LS_FAILS_AFTER_REMOVE') == '1'):
        fail('error: cannot read the global manifest')
    deps = sorted(dependencies())
    print(global_dir + ' node_modules (%d installed)' % len(deps))
    for index, name in enumerate(deps):
        print(('\u2514\u2500\u2500 ' if index == len(deps) - 1 else '\u251c\u2500\u2500 ') + name + '@1.0.0')
elif args == ['pm', 'bin', '-g']:
    if os.environ.get('TEST_BIN_FAILS') == '1':
        fail('error: no global bin directory')
    print(bin_dir)
elif len(args) == 3 and args[:2] == ['remove', '-g']:
    name = args[2]
    if os.environ.get('TEST_REMOVE_FAILS') == '1':
        fail('remove exploded')
    deps = dependencies()
    if name not in deps:
        fail('error: package.json is empty {}, so there is nothing to remove!')
    if os.environ.get('TEST_REMOVE_NOOP') == '1':
        sys.exit(0)
    del deps[name]
    with open(manifest, 'w') as handle:
        json.dump({'dependencies': deps}, handle)
    package_dir = os.path.join(global_dir, 'node_modules', *name.split('/'))
    with open(os.path.join(package_dir, 'package.json')) as handle:
        bins = json.load(handle).get('bin', {})
    for link in bins:
        for suffix in ('', '.bunx', '.exe'):
            path = os.path.join(bin_dir, link + suffix)
            if os.environ.get('TEST_LEAVE_LINK') != '1' and os.path.lexists(path):
                os.unlink(path)
    for current, directories, files in os.walk(package_dir, topdown=False):
        for entry in files:
            os.unlink(os.path.join(current, entry))
        os.rmdir(current)
    open(os.environ['TEST_CAPTURE'] + '.removed', 'w').close()
    print('1 package removed')
else:
    fail('unexpected bun invocation: ' + ' '.join(args))
