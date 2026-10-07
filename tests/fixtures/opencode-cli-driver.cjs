'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const os = require('node:os');
const crypto = require('node:crypto');
const zlib = require('node:zlib');
const {EventEmitter} = require('node:events');
const session = process.argv[2] === '-e' && process.argv[3]?.startsWith('eval(Buffer.from(');
if (process.argv[2] === '-e' && !session) process.exit(0);
assert.ok(session || process.argv[2] === '-');
const home = process.env.HOME, foreign = process.env.FIXTURE_FOREIGN;
assert.ok(home && foreign && path.dirname(home) === path.dirname(foreign));
const windows = process.env.FIXTURE_PLATFORM === 'win32';
const leaf = windows ? 'opencode.exe' : 'opencode';
const destination = path.join(home, '.local/bin', leaf);
const name = `@opencode/cli-${windows ? 'windows' : 'linux'}-x64-baseline`;
const release = '2.0.18', bytes = Buffer.from('INERT official native 2.0.18');
function publish(packageName, version, binary) {
    const tarball = `https://registry.npmjs.org/${packageName}/-/${packageName.split('/').pop()}-${version}.tgz`;
    const blocks = [];
    for (const [filename, contents] of [['package/package.json', JSON.stringify({name: packageName, version})], [`package/bin/${leaf}`, binary]]) {
        const value = Buffer.from(contents), header = Buffer.alloc(512);
        header.write(filename); header.write('0000755\0', 100); header.write('0000000\0', 108); header.write('0000000\0', 116);
        header.write(value.length.toString(8).padStart(11, '0') + '\0', 124);
        header.fill(32, 148, 156); header.write('0', 156); header.write('ustar\0', 257);
        header.write(header.reduce((sum, b) => sum + b, 0).toString(8).padStart(6, '0') + '\0 ', 148);
        blocks.push(header, value, Buffer.alloc((512 - value.length % 512) % 512));
    }
    const archive = zlib.gzipSync(Buffer.concat([...blocks, Buffer.alloc(1024)]));
    return [[`https://registry.npmjs.org/${packageName}/${version}`, Buffer.from(JSON.stringify({name: packageName, version,
        dist: {tarball, integrity: 'sha512-' + crypto.createHash('sha512').update(archive).digest('base64')}}))], [tarball, archive]];
}
const responses = new Map([
    ['https://opencode.ai/update/api/latest/cli/npm', Buffer.from(JSON.stringify({channel: 'latest', name: 'cli', distribution: 'npm',
        version: release, active: true, minimum: false, metadata: {package: '@opencode/cli'}}))],
    ...publish(name, release, bytes),
    ...publish(name, '2.0.10', Buffer.from('INERT official native 2.0.10')),
    ...publish(`opencode-${windows ? 'windows' : 'linux'}-x64-baseline`, '1.2.3', Buffer.from('INERT --user-agent=opencode/1.2.3\0')),
]);
const https = {get(url, options, callback) {
    assert.equal(options.rejectUnauthorized, true);
    assert.ok(responses.has(url), 'only fixture artifact requests allowed');
    const request = new EventEmitter(); request.setTimeout = () => {}; request.destroy = error => request.emit('error', error);
    queueMicrotask(() => {
        const response = new EventEmitter(); response.statusCode = 200; response.resume = () => {};
        if (process.env.FIXTURE_OUTCOME?.startsWith('path-') && !process.env.FIXTURE_OUTCOME.startsWith('path-late')) applyDiscoveryPath();
        callback(response); response.emit('data', responses.get(url)); response.emit('end'); request.emit('close');
    });
    return request;
}};
const writes = new Set(['mkdirSync', 'mkdtempSync', 'writeFileSync', 'renameSync', 'linkSync', 'unlinkSync', 'rmSync', 'rmdirSync', 'chmodSync']);
const proxy = new Proxy(fs, {get(object, key) {
    if (typeof object[key] !== 'function') return object[key];
    return (...args) => {
        if (typeof args[0] === 'string') assert.ok(!/^\/(etc|proc)(\/|$)/.test(args[0]), 'privacy inventory forbidden');
        if (key === 'lstatSync' && typeof args[0] === 'string' && !args[0].startsWith(path.dirname(home) + path.sep) &&
            /^opencode(?:\.exe|\.cmd|\.ps1)?$/.test(path.basename(args[0]))) throw Object.assign(new Error('inert absent command'), {code: 'ENOENT'});
        if (writes.has(key)) {
            for (const file of args.slice(0, ['renameSync', 'linkSync'].includes(key) ? 2 : 1)) assert.ok(file.startsWith(home + path.sep), 'only private account writes allowed');
        }
        if (typeof args[0] === 'string' && args[0].startsWith(foreign)) {
            assert.ok(key === 'lstatSync' || (key === 'accessSync' && args[1] === fs.constants.X_OK), 'foreign content and mutation forbidden');
        }
        if (key === 'rmSync' && ['cleanup', 'path-late-cleanup'].includes(process.env.FIXTURE_OUTCOME)) throw new Error('EXCEPTION_SECRET cleanup output');
        const result = object[key](...args);
        if (key === 'lstatSync') {
            if (args[0] === foreign) result.uid = process.getuid() + 1;
            if (home.startsWith(args[0] + path.sep) && args[0] !== home) { result.uid = 0; result.mode = (result.mode & ~0o777) | 0o755; }
        }
        return result;
    };
}});
const cp = {execFileSync(file, args) {
    if (file === process.env.SETUP_OPENCODE_SHELL) {
        assert.ok(!args.includes('--version'));
        const marker = args.join(' ').match(/opencode-selection-[a-f0-9]+:/)?.[0];
        assert.ok(marker, 'native evidence must be framed');
        if (process.env.FIXTURE_OUTCOME?.startsWith('path-late')) applyDiscoveryPath();
        if (process.env.FIXTURE_SESSION_TRANSACTION === '1') fs.writeFileSync(path.join(home, 'selection-ready'), 'inert query checkpoint');
        return Buffer.from('\n' + marker + (['fresh', 'cleanup'].includes(process.env.FIXTURE_OUTCOME) ? path.join(foreign, leaf) : destination) + marker + '\n');
    }
    assert.ok(file.startsWith(home + path.sep), 'foreign application execution forbidden');
    assert.deepEqual(Array.from(args), ['--version']);
    assert.deepEqual(fs.readFileSync(file), bytes, 'official bytes must precede inert version probes');
    if (file === destination && process.env.FIXTURE_OUTCOME === 'directory-probe') throw new Error('INERT probe failure SECRET');
    return Buffer.from('opencode v2.0.18\n');
}};
const fakeProcess = {platform: windows ? 'win32' : 'linux', env: {...process.env}, getuid: process.getuid,
    report: process.report, stdin: process.stdin, argv: ['node', session ? 'fixture' : '-'],
    getgid: () => assert.fail('group inventory forbidden'), getgroups: () => assert.fail('group inventory forbidden')};
if (windows) {
    fakeProcess.env.SETUP_OPENCODE_FRESH_PATH = '/fixture/persisted-windows-path';
    fakeProcess.env.PATH = fakeProcess.env.PATH.split(':').join(';');
}
let discoveryPathApplied = false;
function applyDiscoveryPath() {
    if (discoveryPathApplied) return;
    discoveryPathApplied = true;
    assert.ok(fakeProcess.env.PATH.split(windows ? ';' : ':').every(dir => path.isAbsolute(dir)), 'incoming PATH must be valid');
    const input = process.env.FIXTURE_PATH_INPUT;
    if (input === undefined) delete fakeProcess.env.PATH;
    else fakeProcess.env.PATH = input.replaceAll('@BIN@', path.dirname(destination)).replaceAll('|', windows ? ';' : ':');
    console.error('STDERR_SECRET private native detail');
}
const modules = {'node:fs': proxy, 'node:https': https, 'node:child_process': cp,
    'node:path': windows ? {...path, delimiter: ';', isAbsolute: path.win32.isAbsolute} : path,
    'node:os': {...os, homedir: () => home, tmpdir: () => path.join(home, 'tmp'), machine: () => 'x86_64',
        userInfo: () => assert.fail('account inventory forbidden')}};
const source = session ? process.argv[3] : fs.readFileSync(0, 'utf8');
if (!session) {
    assert.equal(source.trimEnd(), fs.readFileSync(path.join(__dirname, '../../lib/opencode-cli.cjs'), 'utf8').trimEnd());
    assert.ok(source.includes('module.exports ='));
} else assert.match(source, /^eval\(Buffer\.from\('[A-Za-z0-9+/=]+','base64'\)\.toString\('utf8'\)\)$/);
vm.runInNewContext(source, {require: name => modules[name] || require(name), module: {exports: {}},
    process: fakeProcess, Buffer, URL, setTimeout, clearTimeout, console});
process.on('beforeExit', () => { process.exitCode = fakeProcess.exitCode || 0; });
