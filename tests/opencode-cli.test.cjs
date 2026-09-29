// Version 2 | Last changed: Cover HTTP negotiation and controlled download diagnostics
'use strict';
process.umask(0o077);
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const zlib = require('node:zlib');
const crypto = require('node:crypto');
const policy = require('../lib/opencode-cli.cjs');
const sha = bytes => crypto.createHash('sha512').update(bytes).digest('base64');
function tar(entries) {
    const blocks = [];
    for (const [name, value, type = '0'] of entries) {
        const bytes = Buffer.from(value), h = Buffer.alloc(512);
        h.write(name); h.write('0000755\0', 100); h.write('0000000\0', 108); h.write('0000000\0', 116);
        h.write(bytes.length.toString(8).padStart(11, '0') + '\0', 124);
        h.fill(32, 148, 156); h.write(type, 156); h.write('ustar\0', 257);
        h.write(h.reduce((a, b) => a + b, 0).toString(8).padStart(6, '0') + '\0 ', 148);
        blocks.push(h, bytes, Buffer.alloc((512 - bytes.length % 512) % 512));
    }
    return zlib.gzipSync(Buffer.concat([...blocks, Buffer.alloc(1024)]));
}
function fixture(t) {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'opencode-fixture-'));
    fs.mkdirSync(path.join(home, '.local/bin'), {recursive: true});
    t.after(() => fs.rmSync(home, {recursive: true, force: true}));
    const responses = new Map(), probes = [];
    const latestUrl = 'https://opencode.ai/update/api/latest/cli/npm';
    const latest = {channel: 'latest', name: 'cli', distribution: 'npm', version: '2.0.18',
        active: true, minimum: false, metadata: {package: '@opencode/cli'}};
    responses.set(latestUrl, Buffer.from(JSON.stringify(latest)));
    responses.set('https://registry.npmjs.org/opencode-ai', Buffer.from('{"versions":{"1.2.3":{}}}'));
    responses.set('https://registry.npmjs.org/@opencode/cli', Buffer.from('{"versions":{"2.0.18":{},"3.0.0":{}}}'));
    function publish(name, version, binary = `INERT official ${version}`, extra = []) {
        const basename = name.split('/').pop();
        const url = `https://registry.npmjs.org/${name}/-/${basename}-${version}.tgz`;
        const data = tar([['package/package.json', JSON.stringify({name, version})], ['package/bin/opencode', binary], ...extra]);
        responses.set(url, data);
        responses.set(`https://registry.npmjs.org/${name}/${version}`, Buffer.from(JSON.stringify({name, version,
            dist: {tarball: url, integrity: `sha512-${sha(data)}`}})));
        return Buffer.from(binary);
    }
    const binary = publish('@opencode/cli-linux-x64-baseline', '2.0.18');
    const dest = path.join(home, '.local/bin/opencode');
    const options = {home, target: 'linux-x64-baseline', commands: [], path: path.dirname(dest),
        get: async url => { if (!responses.has(url)) throw new Error('fixture-unexpected-http'); return responses.get(url); },
        probe: (file, release, workspace) => { assert.ok(workspace.startsWith(home) || workspace.startsWith(os.tmpdir()));
            assert.match(fs.readFileSync(file).toString(), /INERT/); probes.push({file, release}); }};
    const setLatest = changes => responses.set(latestUrl, Buffer.from(JSON.stringify({...latest, ...changes})));
    const legacy = (directory = '.opencode/bin', bytes = 'INERT official 1.2.3') => {
        const command = path.join(home, directory, 'opencode');
        fs.mkdirSync(path.dirname(command), {recursive: true}); fs.writeFileSync(command, bytes, {mode: 0o755});
        publish('opencode-linux-x64-baseline', '1.2.3', bytes);
        options.commands.push(command); return command;
    };
    const receipt = (release, bytes, changes = {}) => {
        fs.writeFileSync(dest, bytes, {mode: 0o755});
        fs.writeFileSync(path.join(home, '.local/bin/.setup-opencode-cli.json'), JSON.stringify({
            package: '@opencode/cli-linux-x64-baseline', version: release, sha512: sha(bytes), ...changes}), {mode: 0o600});
        options.commands = [dest];
    };
    return {home, responses, probes, publish, binary, dest, options, setLatest, legacy, receipt};
}
test('strict stable version semantics and native platform matrix', () => {
    for (const value of ['2.0.1-beta', 'v2.0.1', '02.0.1', '2.0', '2.0.1\n', null]) assert.throws(() => policy.version(value));
    assert.equal(policy.compare('2.10.0', '2.9.99'), 1);
    for (const [platform, machine, expected] of [
        ['linux', 'x86_64', 'linux-x64-baseline'], ['linux', 'aarch64', 'linux-arm64'],
        ['darwin', 'arm64', 'darwin-arm64'], ['darwin', 'x86_64', 'darwin-x64-baseline'],
        ['win32', 'AMD64', 'windows-x64-baseline'], ['win32', 'ARM64', 'windows-arm64'],
        ['linux', 'armv7l', null], ['freebsd', 'x86_64', null]]) assert.equal(policy.target(platform, machine, '2.39'), expected);
});
test('fresh, repeated, update and isolated verification', async t => {
    const f = fixture(t);
    assert.equal(await policy.install(f.options), 'installed');
    assert.deepEqual(fs.readFileSync(f.dest), f.binary);
    f.options.commands = [f.dest];
    assert.equal(await policy.install(f.options), 'current');
    f.publish('@opencode/cli-linux-x64-baseline', '2.1.0'); f.setLatest({version: '2.1.0'});
    assert.equal(await policy.install(f.options), 'migrated');
    assert.equal(f.probes.length, 5);
});
test('official newer installed minor and major are preserved without execution', async t => {
    for (const release of ['2.1.0', '3.0.0']) {
        const f = fixture(t), bytes = f.publish('@opencode/cli-linux-x64-baseline', release);
        f.receipt(release, bytes);
        assert.equal(await policy.install(f.options), 'newer');
        assert.deepEqual(fs.readFileSync(f.dest), bytes); assert.equal(f.probes.length, 0);
    }
});
test('unmarked official v2 and newer standalone copies have artifact identity', async t => {
    for (const release of ['2.0.18', '3.0.0']) {
        const f = fixture(t), bytes = f.publish('@opencode/cli-linux-x64-baseline', release);
        const command = f.legacy('.opencode/bin', bytes);
        assert.equal(await policy.install(f.options), release.startsWith('3') ? 'newer' : 'migrated');
        if (release.startsWith('3')) assert.deepEqual(fs.readFileSync(command), bytes);
    }
});
test('standalone migration preserves application data, credentials and shell files', async t => {
    const f = fixture(t), old = f.legacy();
    for (const file of ['.config/opencode/config.json', '.local/share/opencode/auth.json', '.local/share/opencode/sessions', '.bashrc', 'project/opencode.json']) {
        fs.mkdirSync(path.dirname(path.join(f.home, file)), {recursive: true}); fs.writeFileSync(path.join(f.home, file), 'sentinel');
    }
    assert.equal(await policy.install(f.options), 'migrated'); assert.equal(fs.existsSync(old), false);
    for (const file of ['.config/opencode/config.json', '.local/share/opencode/auth.json', '.local/share/opencode/sessions', '.bashrc', 'project/opencode.json']) {
        assert.equal(fs.readFileSync(path.join(f.home, file), 'utf8'), 'sentinel');
    }
    const recovery = fs.readdirSync(path.dirname(f.dest)).find(n => n.startsWith('.setup-opencode-') && fs.lstatSync(path.join(path.dirname(f.dest), n)).isDirectory());
    assert.match(fs.readFileSync(path.join(path.dirname(f.dest), recovery, 'previous-0'), 'utf8'), /1.2.3/);
});
for (const manager of ['npm', 'bun']) test(`${manager} native-copy/wrapper identity migrates only the command, without lifecycle scripts`, async t => {
    const f = fixture(t);
    const root = path.join(f.home, manager === 'npm' ? '.local/lib/node_modules/opencode-ai' : '.bun/install/global/node_modules/opencode-ai');
    fs.mkdirSync(path.join(root, 'bin'), {recursive: true});
    fs.writeFileSync(path.join(root, 'package.json'), '{"name":"opencode-ai","version":"1.2.3"}');
    fs.writeFileSync(path.join(root, 'bin/opencode'), 'INERT wrapper');
    fs.writeFileSync(path.join(root, 'bin/.opencode'), 'INERT official 1.2.3');
    f.publish('opencode-ai', '1.2.3', 'INERT wrapper');
    f.publish('opencode-linux-x64-baseline', '1.2.3');
    const command = path.join(f.home, manager === 'npm' ? '.local/bin/opencode' : '.bun/bin/opencode');
    fs.mkdirSync(path.dirname(command), {recursive: true}); fs.symlinkSync(path.join(root, 'bin/opencode'), command);
    f.options.commands.push(command);
    assert.equal(await policy.install(f.options), 'migrated');
    assert.equal(fs.readFileSync(path.join(root, 'bin/.opencode'), 'utf8'), 'INERT official 1.2.3');
});
for (const modification of ['channel', 'major', 'active', 'minimum', 'package', 'malformed']) test(`rejects ${modification} release metadata before mutations`, async t => {
    const f = fixture(t);
    const changes = {channel: {channel: 'beta'}, major: {version: '3.0.0'}, active: {active: false}, minimum: {minimum: true}, package: {metadata: {package: 'other'}}, malformed: {version: '2.1.0-beta'}};
    f.setLatest(changes[modification]);
    await assert.rejects(policy.install(f.options), /release-metadata|version/);
    assert.equal(fs.existsSync(f.dest), false); assert.equal(f.probes.length, 0);
});
for (const mode of ['download', 'integrity', 'url', 'package']) test(`artifact ${mode} failure preserves the previous native installation`, async t => {
    const f = fixture(t), old = f.legacy();
    const url = 'https://registry.npmjs.org/@opencode/cli-linux-x64-baseline/2.0.18';
    const meta = JSON.parse(f.responses.get(url));
    if (mode === 'download') f.responses.delete(meta.dist.tarball);
    if (mode === 'integrity') f.responses.set(meta.dist.tarball, Buffer.from('tampered'));
    if (mode === 'url') meta.dist.tarball = 'https://attacker.invalid/cli.tgz';
    if (mode === 'package') meta.name = 'attacker';
    f.responses.set(url, Buffer.from(JSON.stringify(meta)));
    await assert.rejects(policy.install(f.options));
    assert.equal(fs.readFileSync(old, 'utf8'), 'INERT official 1.2.3'); assert.equal(f.probes.length, 0);
});
for (const entry of [['../outside', 'x'], ['package/../outside', 'x'], ['package/bin/opencode', '', '2'], ['package/bin/opencode', '', '1']]) {
    test(`archive rejects unsafe entry ${entry.join(':')}`, () => assert.throws(() => policy.unpack(tar([entry]))));
}
test('archive rejects duplicates, truncation and malformed checksums', () => {
    assert.throws(() => policy.unpack(tar([['package/a', 'x'], ['package/a', 'y']])));
    assert.throws(() => policy.unpack(Buffer.from('not gzip')));
    const data = zlib.gunzipSync(tar([['package/a', 'x']])); data[0] = 0;
    assert.throws(() => policy.unpack(zlib.gzipSync(data)));
});
for (const failure of ['staged-version', 'promoted-version', 'unreachable', 'changed-copy']) test(`transaction restores prior command after ${failure}`, async t => {
    const f = fixture(t), old = f.legacy(); let calls = 0;
    f.options.probe = () => {
        calls++;
        if ((failure === 'staged-version' && calls === 1) || (failure === 'promoted-version' && calls === 2)) throw new Error('fixture-probe');
        if (failure === 'changed-copy' && calls === 1) fs.writeFileSync(old, 'user change');
    };
    if (failure === 'unreachable') f.options.path = '/fixture/not/on/path';
    await assert.rejects(policy.install(f.options));
    assert.equal(fs.readFileSync(old, 'utf8'), failure === 'changed-copy' ? 'user change' : 'INERT official 1.2.3');
    assert.equal(fs.existsSync(f.dest), false);
});
test('concurrent destination and occupied lock are preserved without clobbering', async t => {
    for (const mode of ['destination', 'lock']) {
        const f = fixture(t);
        if (mode === 'lock') fs.mkdirSync(path.join(path.dirname(f.dest), '.setup-opencode-cli.lock'));
        else f.options.probe = () => fs.writeFileSync(f.dest, 'concurrent custom command');
        await assert.rejects(policy.install(f.options));
        if (mode === 'destination') assert.equal(fs.readFileSync(f.dest, 'utf8'), 'concurrent custom command');
        else assert.ok(fs.existsSync(path.join(path.dirname(f.dest), '.setup-opencode-cli.lock')));
    }
});
test('partial migration failure restores every already-moved command', async t => {
    const f = fixture(t), first = f.legacy(), second = f.legacy('.bun/bin');
    const rename = fs.renameSync;
    try {
        fs.renameSync = (source, destination) => { if (source === second) throw new Error('inert move failure'); return rename(source, destination); };
        await assert.rejects(policy.install(f.options));
    } finally { fs.renameSync = rename; }
    assert.equal(fs.readFileSync(first, 'utf8'), 'INERT official 1.2.3');
    assert.equal(fs.readFileSync(second, 'utf8'), 'INERT official 1.2.3');
    assert.equal(fs.existsSync(f.dest), false);
});
test('native Bun hardlink with an explicit global pin is preserved', async t => {
    const f = fixture(t), command = f.legacy('.bun/bin');
    const manifest = path.join(f.home, '.bun/install/global/package.json');
    fs.mkdirSync(path.dirname(manifest), {recursive: true});
    fs.writeFileSync(manifest, '{"dependencies":{"opencode-ai":"1.2.3"}}');
    await assert.rejects(policy.install(f.options), /pinned/);
    assert.equal(fs.readFileSync(command, 'utf8'), 'INERT official 1.2.3');
    assert.equal(f.probes.length, 0);
});
test('promotion failure preserves a working managed command and its receipt', async t => {
    const f = fixture(t), previous = f.publish('@opencode/cli-linux-x64-baseline', '2.0.10');
    f.receipt('2.0.10', previous);
    const receiptPath = path.join(path.dirname(f.dest), '.setup-opencode-cli.json');
    const before = fs.readFileSync(receiptPath); let calls = 0;
    f.options.probe = () => { if (++calls === 2) throw new Error('inert failure'); };
    await assert.rejects(policy.install(f.options));
    assert.deepEqual(fs.readFileSync(f.dest), previous); assert.deepEqual(fs.readFileSync(receiptPath), before);
});
test('unknown custom command is not version-probed or removed', async t => {
    const f = fixture(t), old = f.legacy(); fs.writeFileSync(old, 'INERT custom 1.2.3');
    await assert.rejects(policy.install(f.options), /unverified-copy/);
    assert.equal(fs.readFileSync(old, 'utf8'), 'INERT custom 1.2.3'); assert.equal(f.probes.length, 0);
});
test('official bytes at custom or project paths are preserved, not migrated', async t => {
    for (const route of ['binary', 'project-package', 'project-link']) {
        const f = fixture(t);
        if (route === 'binary') f.legacy('project/bin');
        else {
            const root = path.join(f.home, route === 'project-package' ? 'project/node_modules/opencode-ai' : '.local/lib/node_modules/opencode-ai');
            fs.mkdirSync(path.join(root, 'bin'), {recursive: true});
            fs.writeFileSync(path.join(root, 'package.json'), '{"name":"opencode-ai","version":"1.2.3"}');
            fs.writeFileSync(path.join(root, 'bin/opencode.exe'), f.publish('opencode-linux-x64-baseline', '1.2.3'));
            const command = path.join(f.home, 'project/node_modules/.bin/opencode');
            fs.mkdirSync(path.dirname(command), {recursive: true}); fs.symlinkSync(path.join(root, 'bin/opencode.exe'), command);
            f.options.commands.push(command);
        }
        await assert.rejects(policy.install(f.options), /custom-prefix/);
        assert.ok(fs.lstatSync(f.options.commands[0])); assert.equal(f.probes.length, 0);
    }
});
test('linked ancestors, linked metadata, group-writable copies and pins fail closed', async t => {
    for (const unsafe of ['ancestor', 'metadata', 'writable', 'pin']) {
        const f = fixture(t);
        if (unsafe === 'ancestor') { fs.renameSync(path.join(f.home, '.local'), path.join(f.home, 'elsewhere')); fs.symlinkSync('elsewhere', path.join(f.home, '.local')); }
        if (unsafe === 'metadata') fs.symlinkSync('/no/target', path.join(f.home, '.local/bin/.setup-opencode-cli.json'));
        if (unsafe === 'writable') fs.chmodSync(f.legacy(), 0o777);
        if (unsafe === 'pin') f.receipt('2.0.18', f.binary, {pinned: true});
        await assert.rejects(policy.install(f.options)); assert.equal(f.probes.length, 0);
    }
});
test('official embedded version hint avoids an unbounded standalone version search', async t => {
    const f = fixture(t);
    f.legacy('.opencode/bin', 'INERT --user-agent=opencode/1.2.3\u0000');
    f.responses.delete('https://registry.npmjs.org/opencode-ai');
    f.responses.delete('https://registry.npmjs.org/@opencode/cli');
    assert.equal(await policy.install(f.options), 'migrated');
});
test('duplicate pin metadata fails before probes', async t => {
    const f = fixture(t); f.receipt('2.0.18', f.binary);
    const file = path.join(path.dirname(f.dest), '.setup-opencode-cli.json');
    const original = fs.readFileSync(file, 'utf8');
    fs.writeFileSync(file, original.replace('}', ',"pinned":true,"pinned":false}'));
    await assert.rejects(policy.install(f.options), /duplicate-metadata/);
    assert.equal(f.probes.length, 0);
});
test('modern npm postinstall native copy is proven by upstream bytes, not package version', async t => {
    const f = fixture(t), root = path.join(f.home, '.local/lib/node_modules/opencode-ai');
    fs.mkdirSync(path.join(root, 'bin'), {recursive: true});
    fs.writeFileSync(path.join(root, 'package.json'), '{"name":"opencode-ai","version":"1.2.3"}');
    const bytes = f.publish('opencode-linux-x64-baseline', '1.2.3');
    fs.writeFileSync(path.join(root, 'bin/opencode.exe'), bytes);
    fs.symlinkSync(path.join(root, 'bin/opencode.exe'), f.dest); f.options.commands = [f.dest];
    assert.equal(await policy.install(f.options), 'migrated');
});
function virtualPolicy(f, overrides = {}, modules = {}, log = () => assert.fail('unexpected output')) {
    const vm = require('node:vm');
    const mapped = value => typeof value === 'string' && (value === '/opt' || value.startsWith('/opt/')) ? path.join(f.home, 'virtual-opt', value.slice(4)) : value;
    const proxy = new Proxy(fs, {get(object, key) {
        if (typeof object[key] !== 'function') return object[key];
        return (...args) => object[key](...args.map(mapped));
    }});
    const module = {exports: {}};
    const fakeProcess = {platform: 'linux', env: {}, getuid: process.getuid, report: process.report, argv: ['node', 'fixture'], ...overrides};
    vm.runInNewContext(fs.readFileSync(require.resolve('../lib/opencode-cli.cjs'), 'utf8'), {
        require: name => name === 'node:fs' ? proxy : modules[name] || require(name), module, process: fakeProcess,
        Buffer, URL, setTimeout, clearTimeout, console: {log, error: () => assert.fail('unexpected output')},
    });
    return {api: module.exports, mapped, process: fakeProcess};
}
test('real HTTP helper requires verified TLS, rejects redirects/foreign URLs and bounds responses', async t => {
    const f = fixture(t), {EventEmitter} = require('node:events'); let observed, status = 200;
    const https = {get: (url, options, callback) => {
        observed = options;
        const request = new EventEmitter(); request.setTimeout = () => {}; request.destroy = error => request.emit('error', error);
        process.nextTick(() => {
            const response = new EventEmitter(); response.statusCode = status; response.resume = () => {};
            callback(response); response.emit('data', Buffer.from('fixture')); response.emit('end'); request.emit('close');
        });
        return request;
    }};
    const {api} = virtualPolicy(f, {env: {NODE_TLS_REJECT_UNAUTHORIZED: '0'}}, {'node:https': https});
    assert.equal((await api.fetchBytes('https://registry.npmjs.org/fixture')).toString(), 'fixture');
    assert.equal(observed.rejectUnauthorized, true);
    for (const url of ['http://registry.npmjs.org/fixture', 'https://attacker.invalid/fixture', 'https://user:password@registry.npmjs.org/fixture']) {
        assert.throws(() => api.fetchBytes(url), /url/);
    }
    status = 302; await assert.rejects(api.fetchBytes('https://registry.npmjs.org/fixture'), /download/);
    status = 200; await assert.rejects(api.fetchBytes('https://registry.npmjs.org/fixture', 1), /download/);
});
// Model npm's content negotiation at the HTTPS boundary, not by replacing fetchBytes.
function httpPolicy(f, replies = new Map(), overrides = {}, log) {
    const {EventEmitter} = require('node:events'), requests = [];
    const expected = new Map([
        ['https://opencode.ai/update/api/latest/cli/npm', 'application/json'],
        ['https://registry.npmjs.org/opencode-ai', 'application/vnd.npm.install-v1+json'],
        ['https://registry.npmjs.org/@opencode/cli', 'application/vnd.npm.install-v1+json'],
    ]);
    for (const url of f.responses.keys()) {
        if (!expected.has(url)) expected.set(url, url.endsWith('.tgz') ? 'application/octet-stream' : 'application/json');
    }
    const https = {get: (url, options, callback) => {
        requests.push({url, options});
        assert.equal(options.rejectUnauthorized, true);
        assert.ok(expected.has(url), 'unexpected offline request');
        const request = new EventEmitter();
        request.setTimeout = () => request;
        request.destroy = error => { request.emit('error', error); request.emit('close'); };
        queueMicrotask(() => {
            const reply = replies.get(url) || {};
            if (reply.networkError) { request.destroy(new Error('SECRET transport detail')); return; }
            const response = new EventEmitter(); response.resume = () => {};
            response.statusCode = reply.status ?? (options.headers.Accept === expected.get(url) ? 200 : 406);
            callback(response);
            response.emit('data', reply.body || f.responses.get(url));
            if (reply.streamError) response.emit('error', new Error('SECRET response detail'));
            else response.emit('end');
            request.emit('close');
        });
        return request;
    }};
    return {...virtualPolicy(f, overrides, {
        'node:https': https,
        'node:os': {...os, homedir: () => f.home, machine: () => 'x86_64'},
        'node:child_process': {execFileSync: () => assert.fail('unexpected application execution')},
    }, log), requests, expected};
}
for (const name of ['opencode-ai', '@opencode/cli', '@opencode%2fcli', '%40opencode%2Fcli']) {
    test(`real HTTP helper negotiates index, version and tarball for ${name}`, async t => {
        const f = fixture(t), base = `https://registry.npmjs.org/${name}`;
        const endpoints = [[base, 'application/vnd.npm.install-v1+json'],
            [base + '/2.0.18', 'application/json'], [base + '/-/cli-2.0.18.tgz', 'application/octet-stream']];
        for (const [url] of endpoints) f.responses.set(url, Buffer.from('fixture'));
        const h = httpPolicy(f);
        for (const [url, accept] of endpoints) {
            h.expected.set(url, accept);
            assert.equal((await h.api.fetchBytes(url)).toString(), 'fixture');
            assert.equal(h.requests.at(-1).options.headers.Accept, accept);
        }
    });
}
for (const migration of [false, true]) test(`real HTTP helper completes inert ${migration ? 'migration' : 'installation'}`, async t => {
    const f = fixture(t);
    if (migration) f.legacy();
    const h = httpPolicy(f);
    assert.equal(await h.api.install({...f.options, get: undefined}), migration ? 'migrated' : 'installed');
    assert.deepEqual(fs.readFileSync(f.dest), f.binary);
    assert.equal(f.probes.length, 2);
    assert.ok(h.requests.some(r => r.url === 'https://opencode.ai/update/api/latest/cli/npm'));
    if (migration) for (const url of ['https://registry.npmjs.org/opencode-ai', 'https://registry.npmjs.org/@opencode/cli']) {
        assert.ok(h.requests.some(r => r.url === url));
    }
});
test('real artifact helper retrieves unscoped package metadata and bytes', async t => {
    const f = fixture(t); f.publish('opencode-ai', '1.2.3', 'INERT wrapper');
    const {api} = httpPolicy(f);
    const files = await api.artifact('opencode-ai', '1.2.3');
    assert.equal(files.get('package/bin/opencode').toString(), 'INERT wrapper');
    assert.equal(f.probes.length, 0);
});
for (const [operation, url] of [
    ['latest-release', 'https://opencode.ai/update/api/latest/cli/npm'],
    ['package-index', 'https://registry.npmjs.org/opencode-ai'],
    ['package-version', 'https://registry.npmjs.org/@opencode/cli-linux-x64-baseline/2.0.18'],
    ['artifact-download', 'https://registry.npmjs.org/@opencode/cli-linux-x64-baseline/-/cli-linux-x64-baseline-2.0.18.tgz'],
]) test(`real HTTP ${operation} failures retain only controlled status and operation`, async t => {
    const f = fixture(t);
    // Force index discovery on the same actual installation path.
    if (operation === 'package-index') f.legacy();
    const replies = new Map(), h = httpPolicy(f, replies);
    for (const reply of [{status: 406}, {status: 302}, {status: 503}, {networkError: true}, {streamError: true}]) {
        replies.set(url, {...reply, body: Buffer.from('SECRET body https://private.invalid/token')});
        await assert.rejects(h.api.install({...f.options, get: undefined}), error => {
            assert.equal(h.api.failureResult(error), `opencode-cli:download-failed:${operation}:http-${reply.status || (reply.streamError ? 200 : 'unknown')}`);
            return true;
        });
        assert.equal(fs.existsSync(f.dest), false);
        assert.equal(f.probes.length, 0);
        assert.deepEqual(fs.readdirSync(path.dirname(f.dest)), []);
    }
    for (const status of ['406 SECRET', '406', 99, 600, 406.5]) {
        replies.set(url, {status});
        await assert.rejects(h.api.fetchBytes(url), error => {
            assert.equal(h.api.failureResult(error), `opencode-cli:download-failed:${operation}:http-unknown`);
            return true;
        });
    }
});
test('actual core entry point emits the controlled failure and nonzero exit status', async t => {
    const f = fixture(t), url = 'https://registry.npmjs.org/@opencode/cli-linux-x64-baseline/2.0.18';
    let h;
    const result = await new Promise(resolve => {
        h = httpPolicy(f, new Map([[url, {status: 406, body: Buffer.from('SECRET response')}]]),
            {argv: ['node', '-'], env: {PATH: path.dirname(f.dest)}}, resolve);
    });
    assert.equal(result, 'opencode-cli:download-failed:package-version:http-406');
    assert.equal(h.process.exitCode, 1);
    assert.equal(fs.existsSync(f.dest), false);
    assert.equal(f.probes.length, 0);
});
test('failure serialization never echoes arbitrary exceptions or forged diagnostics', async t => {
    const f = fixture(t), url = 'https://opencode.ai/update/api/latest/cli/npm';
    const {api} = httpPolicy(f, new Map([[url, {status: 406}]]));
    for (const error of [new Error('SECRET exception'), {operation: 'package-version', status: 406},
        new Error('opencode-cli:download-failed:package-version:http-406'), null]) {
        assert.equal(api.failureResult(error), 'opencode-cli:failed');
    }
    await assert.rejects(api.fetchBytes(url), error => {
        error.operation = 'SECRET URL';
        assert.equal(api.failureResult(error), 'opencode-cli:failed');
        return true;
    });
    assert.equal(api.failureResult(new Error('recovery-required')), 'opencode-cli:recovery-required');
});
test('real version-probe helper isolates HOME, cwd and application credentials', t => {
    const f = fixture(t); let observed;
    const {api} = virtualPolicy(f, {env: {OPENCODE_API_KEY: 'fixture-secret', OPENCODE_CONFIG: '/fixture/config', NODE_OPTIONS: '--invalid'}},
        {'node:child_process': {execFileSync: (file, args, options) => { observed = {file, args, options}; return Buffer.from('2.0.18\n'); }}});
    api.probe(f.dest, '2.0.18', f.home);
    assert.deepEqual(Array.from(observed.args), ['--version']);
    assert.ok(observed.options.cwd.startsWith(f.home));
    assert.equal(observed.options.env.HOME, observed.options.cwd);
    assert.equal(observed.options.env.OPENCODE_API_KEY, undefined);
    assert.equal(observed.options.env.OPENCODE_CONFIG, undefined);
    assert.equal(observed.options.env.NODE_OPTIONS, undefined);
    assert.equal(observed.options.timeout, 20000);
});
test('Homebrew receipt, official native identity, pin and macOS readiness gates', async t => {
    for (const mode of ['migrate', 'pinned', 'unready', 'custom-tap']) {
        const f = fixture(t), {api, mapped} = virtualPolicy(f, {platform: 'darwin', env: {SETUP_OPENCODE_BREW_READY: mode === 'unready' ? '0' : '1'}});
        const command = '/opt/homebrew/bin/opencode';
        fs.mkdirSync(mapped('/opt/homebrew/Cellar/opencode/1.2.3/bin'), {recursive: true});
        fs.mkdirSync(mapped('/opt/homebrew/bin'), {recursive: true});
        fs.writeFileSync(mapped('/opt/homebrew/Cellar/opencode/1.2.3/bin/opencode'), f.publish('opencode-linux-x64-baseline', '1.2.3'));
        fs.writeFileSync(mapped('/opt/homebrew/Cellar/opencode/1.2.3/INSTALL_RECEIPT.json'), JSON.stringify({source: {tap: mode === 'custom-tap' ? 'custom/tap' : 'anomalyco/tap'}}));
        fs.symlinkSync('../Cellar/opencode/1.2.3/bin/opencode', mapped(command));
        if (mode === 'pinned') {
            fs.mkdirSync(mapped('/opt/homebrew/var/homebrew/pinned'), {recursive: true});
            fs.symlinkSync('/ignored', mapped('/opt/homebrew/var/homebrew/pinned/opencode'));
        }
        f.options.commands = [command];
        if (mode === 'migrate') {
            assert.equal(await api.install(f.options), 'migrated');
            assert.equal(fs.existsSync(mapped(command)), false);
            assert.ok(fs.existsSync(mapped('/opt/homebrew/Cellar/opencode/1.2.3/bin/opencode')));
        } else {
            await assert.rejects(api.install(f.options));
            assert.equal(fs.readlinkSync(mapped(command)), '../Cellar/opencode/1.2.3/bin/opencode');
            assert.equal(f.probes.length, 0);
        }
    }
});
test('Rosetta legacy x64 bytes can migrate to an ARM64 native target without executing the old binary', async t => {
    const f = fixture(t), {api} = virtualPolicy(f, {platform: 'darwin'});
    const command = f.legacy();
    f.publish('opencode-darwin-x64', '1.2.3');
    f.publish('@opencode/cli-darwin-arm64', '2.0.18'); f.options.target = 'darwin-arm64';
    assert.equal(await api.install(f.options), 'migrated');
    assert.equal(f.probes.some(p => p.file === command), false);
});
test('Linux libc selection rejects uncertainty and selects musl without executing ldd', t => {
    const f = fixture(t);
    const original = fs.readdirSync;
    try {
        fs.readdirSync = file => file === '/lib' ? ['ld-musl-x86_64.so.1'] : original(file);
        assert.equal(policy.target('linux', 'x86_64', ''), 'linux-x64-baseline-musl');
        fs.readdirSync = file => file === '/lib' ? [] : original(file);
        assert.throws(() => policy.target('linux', 'x86_64', ''), /libc/);
        assert.equal(fs.existsSync(f.dest), false);
    } finally { fs.readdirSync = original; }
});
test('native npm Windows shim templates match the installed cmd-shim implementation', {skip: !process.env.OPENCODE_TEST_CMD_SHIM}, async t => {
    const f = fixture(t), binary = path.join(f.home, 'node_modules/opencode-ai/bin/opencode.exe');
    fs.mkdirSync(path.dirname(binary), {recursive: true}); fs.writeFileSync(binary, 'INERT native fixture');
    await require(process.env.OPENCODE_TEST_CMD_SHIM)(binary, path.join(f.home, 'opencode'));
    for (const [name, expected] of Object.entries(policy.windowsNpmShims())) assert.equal(fs.readFileSync(path.join(f.home, name), 'utf8'), expected);
});
test('Windows npm command shims migrate only after official native-byte verification', async t => {
    const f = fixture(t), {api} = virtualPolicy(f, {platform: 'win32', env: {SETUP_OPENCODE_ACL_VERIFIED: '1'}});
    const directory = path.join(f.home, 'AppData/Roaming/npm'), root = path.join(directory, 'node_modules/opencode-ai');
    fs.mkdirSync(path.join(root, 'bin'), {recursive: true});
    fs.writeFileSync(path.join(root, 'package.json'), '{"name":"opencode-ai","version":"1.2.3"}');
    const bytes = Buffer.from('INERT native 1.2.3'), modern = Buffer.from('INERT native 2.0.18');
    function windowsArtifact(name, release, contents) {
        const url = `https://registry.npmjs.org/${name}/-/${name.split('/').pop()}-${release}.tgz`;
        const archive = tar([['package/package.json', JSON.stringify({name, version: release})], ['package/bin/opencode.exe', contents]]);
        f.responses.set(url, archive); f.responses.set(`https://registry.npmjs.org/${name}/${release}`,
            Buffer.from(JSON.stringify({name, version: release, dist: {tarball: url, integrity: `sha512-${sha(archive)}`}})));
    }
    windowsArtifact('opencode-windows-x64-baseline', '1.2.3', bytes);
    windowsArtifact('@opencode/cli-windows-x64-baseline', '2.0.18', modern);
    fs.writeFileSync(path.join(root, 'bin/opencode.exe'), bytes);
    for (const [name, value] of Object.entries(api.windowsNpmShims())) {
        const command = path.join(directory, name); fs.writeFileSync(command, value); f.options.commands.push(command);
    }
    f.options.target = 'windows-x64-baseline';
    assert.equal(await api.install(f.options), 'migrated');
    assert.deepEqual(fs.readFileSync(f.dest + '.exe'), modern);
    assert.deepEqual(fs.readFileSync(path.join(root, 'bin/opencode.exe')), bytes);
});
test('unsupported architecture performs no HTTP or filesystem provisioning', async () => {
    assert.equal(await policy.install({target: null, home: '/does/not/exist', get: () => assert.fail('HTTP')}), 'unsupported');
});
