#!/usr/bin/env python3
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

REPLAY = r"""
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const source = fs.readFileSync(process.argv[1], 'utf8');
const trace = [];
const capture = [
    ['/', 0, 0, 0o40755, 'Directory', 23, 16777229, 2],
    ['/opt', 0, 0, 0o40755, 'Directory', 3, 16777229, 21005],
    ['/opt/homebrew', 501, 80, 0o40755, 'Directory', 40, 16777229, 2396115],
    ['/opt/homebrew/bin', 501, 80, 0o40775, 'Directory', 652, 16777229, 2557632],
    ['/opt/homebrew/bin/opencode', 501, 80, 0o120755, 'Symbolic Link', 1, 16777229, 13607738],
];
const rows = new Map(capture.map(([file, uid, gid, mode, kind, nlink, dev, ino]) =>
    [file, {uid, gid, mode, kind, nlink, dev, ino}]));
const variant = process.argv[2];
assert.ok(['captured', 'minimal', 'mode-only', 'root-owner', 'foreign-owner', 'root-account',
    'world-write', 'file', 'symlink', 'prefix-write', 'usr-local', 'linux', 'freebsd'].includes(variant));
if (variant === 'minimal') {
    for (const row of rows.values()) {
        for (const key of ['gid', 'nlink', 'dev', 'ino']) delete row[key];
    }
}
const bin = rows.get('/opt/homebrew/bin');
if (variant === 'mode-only') bin.mode = 0o40755;
if (variant === 'root-owner') bin.uid = 0;
if (variant === 'foreign-owner') bin.uid = 502;
if (variant === 'root-account') for (const row of rows.values()) row.uid = 0;
if (variant === 'world-write') bin.mode = 0o40777;
if (variant === 'file') { bin.kind = 'Regular File'; bin.mode = 0o100775; }
if (variant === 'symlink') { bin.kind = 'Symbolic Link'; bin.mode = 0o120775; }
if (variant === 'prefix-write') rows.get('/opt/homebrew').mode = 0o40775;
let command = '/opt/homebrew/bin/opencode';
if (variant === 'usr-local') {
    const renamed = [...rows].map(([file, row]) => [file.replace('/opt/homebrew', '/usr/local').replace(/^\/opt$/, '/usr'), row]);
    rows.clear(); for (const [file, row] of renamed) rows.set(file, row);
    command = '/usr/local/bin/opencode';
}
const unknown = label => { throw new Error(`uncaptured-operation:${label}`); };
function strict(object, label) {
    return new Proxy(object, {get(target, key) {
        if (!Object.hasOwn(target, key)) return unknown(`${label}.${String(key)}`);
        return target[key];
    }});
}
const noLinkTarget = new Error('uncaptured-link-target');
const mockedFs = strict({
    lstatSync(file) {
        trace.push(['lstat', file]);
        if (!rows.has(file)) return unknown('lstat-path');
        const row = rows.get(file);
        return strict({...row,
            isDirectory: () => row.kind === 'Directory',
            isSymbolicLink: () => row.kind === 'Symbolic Link',
            isFile: () => row.kind === 'Regular File',
        }, 'stat');
    },
    readlinkSync(file) {
        trace.push(['readlink', file]);
        assert.equal(file, command);
        throw noLinkTarget;
    },
}, 'fs');
const modules = {
    'node:fs': mockedFs, 'node:path': path.posix,
    'node:util': {types: {isNativeError: require('node:util').types.isNativeError}},
};
for (const name of ['os', 'https', 'crypto', 'zlib', 'child_process']) {
    modules[`node:${name}`] = strict({}, name);
}
const fixtureRequire = name => {
    if (!Object.hasOwn(modules, name)) return unknown('require');
    return modules[name];
};
fixtureRequire.main = null;
const moduleFixture = {exports: {}};
const fixtureProcess = strict({platform: ['linux', 'freebsd'].includes(variant) ? variant : 'darwin',
    getuid: () => variant === 'root-account' ? 0 : 501,
    argv: ['fixture-node', 'not-an-entry-point']}, 'process');
vm.runInNewContext(source, {require: fixtureRequire, module: moduleFixture,
    process: fixtureProcess, console: strict({}, 'console')}, {timeout: 1000});
assert.deepEqual(trace, [], 'definitions import must have no filesystem effects');
const api = moduleFixture.exports;
let error;
try { api.brewCopy(command); }
catch (caught) { error = caught; }
assert.ok(error, 'this incomplete capture cannot establish full preflight success');
const result = error === noLinkTarget ? 'uncaptured-link-target' : api.failureResult(error);
assert.ok(['uncaptured-link-target', 'opencode-cli:policy-failed:homebrew-preflight:brew-path'].includes(result),
    'unknown operations must fail, never silently become fixture evidence');
console.log(JSON.stringify({variant, result, trace}));
"""


def replay(variant):
    node = shutil.which('node')
    if not node:
        raise AssertionError('existing native Node required')
    with tempfile.TemporaryDirectory(prefix='opencode-mac-preflight-') as tmp:
        output = Path(tmp) / 'stdout'
        errors = Path(tmp) / 'stderr'
        with output.open('x') as stdout, errors.open('x') as stderr:
            child = subprocess.run(
                [node, '-e', REPLAY, str(ROOT / 'lib/opencode-cli.cjs'), variant],
                stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                close_fds=True, timeout=5, check=False,
            )
        if child.returncode:
            raise AssertionError('isolated replay failed: ' + errors.read_text())
        result = json.loads(output.read_text())
    print(json.dumps(result), flush=True)
    return result


class MacPreflightCapture(unittest.TestCase):
    def test_approved_capture_reaches_uncaptured_target_not_install_success(self):
        for variant in ('captured', 'minimal'):
            with self.subTest(variant=variant):
                observed = replay(variant)
                self.assertEqual(observed['result'], 'uncaptured-link-target')
                self.assertEqual(observed['trace'], [
                    ['lstat', '/'], ['lstat', '/opt'], ['lstat', '/opt/homebrew'],
                    ['lstat', '/opt/homebrew/bin'], ['lstat', '/opt/homebrew/bin/opencode'],
                    ['readlink', '/opt/homebrew/bin/opencode'],
                ])

    def test_other_owners_modes_types_paths_and_platforms_still_refuse(self):
        for variant in ('root-owner', 'foreign-owner', 'root-account', 'world-write',
                        'file', 'symlink', 'prefix-write', 'usr-local', 'linux', 'freebsd'):
            with self.subTest(variant=variant):
                observed = replay(variant)
                self.assertEqual(observed['result'],
                                 'opencode-cli:policy-failed:homebrew-preflight:brew-path')
                expected = ['/', '/opt', '/opt/homebrew', '/opt/homebrew/bin']
                if variant == 'prefix-write':
                    expected.pop()
                if variant == 'usr-local':
                    expected = ['/', '/usr', '/usr/local', '/usr/local/bin']
                self.assertEqual(observed['trace'], [['lstat', file] for file in expected])

    def test_mode_only_variation_reaches_uncaptured_target_not_success(self):
        observed = replay('mode-only')
        self.assertEqual(observed['result'], 'uncaptured-link-target')
        self.assertEqual(observed['trace'], [
            ['lstat', '/'], ['lstat', '/opt'], ['lstat', '/opt/homebrew'],
            ['lstat', '/opt/homebrew/bin'], ['lstat', '/opt/homebrew/bin/opencode'],
            ['readlink', '/opt/homebrew/bin/opencode'],
        ])


if __name__ == '__main__':
    unittest.main()
