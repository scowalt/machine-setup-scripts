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
const nativeExecFileSync = require('node:child_process').execFileSync;
process.env.SETUP_OPENCODE_SHELL = '/fixture/fish';
const sha = bytes => crypto.createHash('sha512').update(bytes).digest('base64');
function selectionOutput(file, args, output) {
    if (file === '/usr/bin/fish') return output;
    const marker = args.join(' ').match(/opencode-selection-[a-f0-9]+:/)?.[0];
    assert.ok(marker, 'fresh query must frame native evidence');
    return Buffer.from('\n' + marker + output.toString().replace(/\r?\n$/, '') + marker + '\n');
}
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
    const f = {home, responses, probes, publish, binary, dest, options, setLatest, legacy, receipt};
    f.shellBoundary = () => Buffer.from((f.shellSelection || dest) + '\n');
    t.mock.method(require('node:child_process'), 'execFileSync', (file, ...args) => {
        assert.equal(file, '/fixture/fish', 'unmocked application execution forbidden');
        return selectionOutput(file, args[0], f.shellBoundary(file, ...args));
    });
    return f;
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
test('account-owned ordinary directories retain their modes through installation, repeat and update', async t => {
    for (const platform of ['linux', 'darwin']) for (const mode of [0o700, 0o755, 0o775, 0o2775]) {
        const f = fixture(t), directories = [f.home, path.join(f.home, '.local'), path.dirname(f.dest)];
        for (const directory of directories) fs.chmodSync(directory, mode);
        const snapshot = () => directories.map(directory => {
            const s = fs.lstatSync(directory); return [s.uid, s.gid, s.mode, s.dev, s.ino];
        });
        const before = snapshot();
        const forbidden = () => assert.fail('directory privacy inventory forbidden');
        const {api} = virtualPolicy(f, {platform, getgid: forbidden, getgroups: forbidden}, {
            'node:os': {...os, userInfo: forbidden},
            'node:child_process': {execFileSync: forbidden, execSync: forbidden, spawnSync: forbidden, spawn: forbidden, exec: forbidden, execFile: forbidden},
            'node:fs': new Proxy(fs, {get(object, key) {
                if (key === 'chownSync') return forbidden;
                if (key === 'chmodSync') return (file, value) => {
                    assert.ok(path.dirname(file) === path.dirname(f.dest) && path.basename(file).startsWith('.setup-opencode-'));
                    assert.equal(value, 0o700); return fs.chmodSync(file, value);
                };
                if (typeof object[key] !== 'function') return object[key];
                return (...args) => {
                    if (typeof args[0] === 'string') assert.ok(!/^\/(etc|proc|usr)(\/|$)/.test(args[0]), 'privacy-proof paths forbidden');
                    return object[key](...args);
                };
            }}),
        });
        assert.equal(await api.install(f.options), 'installed');
        f.options.commands = [f.dest];
        assert.equal(await api.install(f.options), 'current');
        assert.deepEqual(snapshot(), before);
        f.publish('@opencode/cli-linux-x64-baseline', '2.1.0'); f.setLatest({version: '2.1.0'});
        assert.equal(await api.install(f.options), 'migrated');
        assert.deepEqual(snapshot(), before);
        assert.equal(fs.statSync(path.join(path.dirname(f.dest), fs.readdirSync(path.dirname(f.dest))
            .find(name => name.startsWith('.setup-opencode-') && fs.lstatSync(path.join(path.dirname(f.dest), name)).isDirectory()))).mode & 0o777, 0o700);
        assert.equal(f.probes.length, 5);
    }
});
for (const phase of ['staged', 'promoted', 'current', 'recovery']) for (const change of ['mode', 'group', 'identity', 'owner', 'type']) {
    test(`account directory ${change} change invalidates ${phase} evidence`, async t => {
        const f = fixture(t), boundary = path.dirname(f.dest), original = f.legacy();
        fs.chmodSync(boundary, 0o775);
        const overrides = {};
        const mutate = () => {
            if (change === 'mode') fs.chmodSync(boundary, 0o2775);
            else if (change === 'type') overrides.mode = 0o100775;
            else {
                const key = {group: 'gid', identity: 'ino', owner: 'uid'}[change];
                overrides[key] = fs.lstatSync(boundary)[key] + 1;
            }
        };
        const {api} = virtualPolicy(f, {}, {'node:fs': new Proxy(fs, {get(object, key) {
            if (key === 'lstatSync') return file => {
                const info = fs.lstatSync(file);
                if (file === boundary) Object.assign(info, overrides);
                return info;
            };
            return object[key];
        }})});
        if (phase === 'current') {
            f.receipt('2.0.18', f.binary);
            f.shellBoundary = () => { mutate(); return Buffer.from(f.dest + '\n'); };
        } else {
            const probe = f.options.probe;
            f.options.probe = (...args) => {
                probe(...args);
                if (f.probes.length === (phase === 'staged' ? 1 : 2)) {
                    mutate();
                    if (phase === 'recovery') throw new Error('INERT probe failed');
                }
            };
        }
        await assert.rejects(api.install(f.options));
        assert.equal(fs.statSync(boundary).mode & 0o7777, change === 'mode' ? 0o2775 : 0o775);
        if (phase === 'staged' || phase === 'current') {
            assert.equal(fs.readFileSync(original, 'utf8'), 'INERT official 1.2.3');
            assert.equal(fs.existsSync(f.dest), phase === 'current');
        } else {
            assert.equal(fs.existsSync(original), false, 'uncertain rollback must retain the private backup');
            assert.equal(fs.existsSync(path.join(boundary, '.setup-opencode-cli.lock')), true);
            const stage = fs.readdirSync(boundary).find(name => name.startsWith('.setup-opencode-') && name !== '.setup-opencode-cli.lock' && fs.lstatSync(path.join(boundary, name)).isDirectory());
            assert.equal(fs.statSync(path.join(boundary, stage)).mode & 0o777, 0o700);
            assert.equal(fs.readFileSync(path.join(boundary, stage, 'previous-0'), 'utf8'), 'INERT official 1.2.3');
        }
    });
}
for (const ancestor of ['.local', '.local/bin']) for (const substitution of ['directory', 'link']) for (const probeFails of [false, true]) {
    test(`staged ${ancestor} ${substitution} substitution preserves cleanup trees and ${probeFails ? 'probe' : 'directory'} failure`, async t => {
        const f = fixture(t), original = f.legacy(), boundary = path.join(f.home, ancestor);
        fs.chmodSync(boundary, 0o2775);
        const saved = path.join(f.home, 'saved-ancestor'), replacement = path.join(f.home, 'replacement');
        const snapshot = directory => fs.readdirSync(directory).sort().flatMap(name => {
            const file = path.join(directory, name), info = fs.lstatSync(file);
            return [[file, info.dev, info.ino, info.uid, info.gid, info.mode, info.nlink, info.size, info.mtimeMs, info.ctimeMs,
                info.isFile() ? fs.readFileSync(file) : null], ...(info.isDirectory() ? snapshot(file) : [])];
        });
        let replacementBin, savedBin, savedStage, replacementBefore, savedBefore;
        const {api} = virtualPolicy(f, {}, {'node:child_process': {execFileSync: (file, args, options) => {
            assert.deepEqual(Array.from(args), ['--version']);
            assert.deepEqual(fs.readFileSync(file), f.binary, 'official inert bytes precede the staged probe');
            assert.equal(f.probes.length, 0, 'no promotion or subsequent probe is allowed');
            f.probes.push({file});
            const stage = path.dirname(file), relativeBin = path.relative(boundary, path.dirname(f.dest));
            assert.equal(path.dirname(options.cwd), stage);
            fs.renameSync(boundary, saved);
            if (substitution === 'link') {
                fs.mkdirSync(replacement);
                fs.symlinkSync(replacement, boundary);
            } else fs.mkdirSync(boundary);
            replacementBin = path.join(substitution === 'link' ? replacement : boundary, relativeBin);
            savedBin = path.join(saved, relativeBin);
            savedStage = path.join(savedBin, path.basename(stage));
            fs.mkdirSync(replacementBin, {recursive: true});
            const replacementStage = path.join(replacementBin, path.basename(stage));
            fs.mkdirSync(replacementStage, {mode: 0o700});
            fs.writeFileSync(path.join(replacementStage, 'sentinel'), 'INERT replacement stage must survive');
            fs.mkdirSync(path.join(replacementBin, '.setup-opencode-cli.lock'), {mode: 0o700});
            fs.writeFileSync(path.join(replacementBin, 'sentinel'), 'INERT unrelated replacement must survive');
            replacementBefore = snapshot(replacementBin);
            savedBefore = snapshot(savedBin);
            if (probeFails) throw new Error('SECRET original probe exception');
            return Buffer.from('opencode v2.0.18\n');
        }}});
        let diagnostic;
        await assert.rejects(api.install({...f.options, probe: undefined}), error => {
            diagnostic = api.failureResult(error); return true;
        });
        assert.deepEqual(snapshot(replacementBin), replacementBefore, 'cleanup must not touch the substituted stage, lock or sentinels');
        assert.deepEqual(snapshot(savedBin), savedBefore, 'uncertain cleanup must retain original private transaction evidence');
        assert.equal(fs.lstatSync(saved).mode & 0o7777, 0o2775);
        for (const directory of [savedStage, path.join(savedBin, '.setup-opencode-cli.lock')]) {
            assert.equal(fs.lstatSync(directory).mode & 0o777, 0o700);
        }
        assert.deepEqual(fs.readFileSync(path.join(savedStage, 'opencode')), f.binary);
        assert.equal(fs.readFileSync(original, 'utf8'), 'INERT official 1.2.3');
        assert.equal(fs.existsSync(f.dest), false);
        assert.equal(fs.existsSync(path.join(savedBin, '.setup-opencode-cli.json')), false);
        assert.equal(diagnostic, 'opencode-cli:recovery-required:policy-failed:installation:' + (probeFails ? 'version-probe' : 'changed-copy'));
    });
}
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
        f.options.path += path.delimiter + path.dirname(command);
        if (release.startsWith('3')) f.shellSelection = command;
        assert.equal(await policy.install(f.options), release.startsWith('3') ? 'newer' : 'migrated');
        if (release.startsWith('3')) assert.deepEqual(fs.readFileSync(command), bytes);
    }
});
test('fresh native shell disagreement rolls back an otherwise verified account-local update', async t => {
    const f = fixture(t), previous = f.publish('@opencode/cli-linux-x64-baseline', '2.0.10');
    f.receipt('2.0.10', previous);
    const receipt = path.join(path.dirname(f.dest), '.setup-opencode-cli.json'), before = fs.readFileSync(receipt);
    f.shellBoundary = (file, args, options) => {
            assert.equal(file, '/fixture/fish');
            assert.equal(options.cwd, f.home);
            assert.equal(options.env.PATH, '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin');
            assert.equal(options.env.MISE_AUTO_INSTALL, 'false');
            assert.equal(options.stdio[2], 'ignore');
            assert.ok(!args.join(' ').includes('--version'), 'resolution must never execute OpenCode');
            return Buffer.from('/another-account/bin/opencode\n');
    };
    const {api} = virtualPolicy(f);
    await assert.rejects(api.install(f.options), error => {
        assert.equal(api.failureResult(error), 'opencode-cli:policy-failed:fresh-shell-selection:command-conflict');
        return true;
    });
    assert.deepEqual(fs.readFileSync(f.dest), previous);
    assert.deepEqual(fs.readFileSync(receipt), before);
});
test('fresh-shell startup cannot invalidate official bytes before the current command probe', async t => {
    const f = fixture(t); f.receipt('2.0.18', f.binary);
    f.shellBoundary = () => { fs.writeFileSync(f.dest, 'INERT independently changed'); return Buffer.from(f.dest + '\n'); };
    await assert.rejects(policy.install(f.options), /changed-copy/);
    assert.equal(f.probes.length, 0);
    assert.equal(fs.readFileSync(f.dest, 'utf8'), 'INERT independently changed');
});
test('fresh-shell changes cannot be accepted as a promoted or preserved newer command', async t => {
    for (const state of ['promoted', 'newer']) {
        const f = fixture(t);
        let selected = f.dest;
        if (state === 'newer') {
            selected = f.legacy('.opencode/bin', f.publish('@opencode/cli-linux-x64-baseline', '3.0.0'));
            f.options.path = path.dirname(selected);
        }
        f.shellBoundary = () => { fs.writeFileSync(selected, 'INERT independently changed'); return Buffer.from(selected + '\n'); };
        await assert.rejects(policy.install(f.options), error => {
            assert.equal(policy.failureResult(error), state === 'promoted'
                ? 'opencode-cli:recovery-required:policy-failed:installation:changed-copy'
                : 'opencode-cli:policy-failed:installation:changed-copy'); return true;
        });
        assert.equal(fs.readFileSync(selected, 'utf8'), 'INERT independently changed');
        assert.equal(fs.existsSync(path.join(path.dirname(f.dest), '.setup-opencode-cli.json')), false);
    }
});
test('setup cached command cannot override verified PATH selection', async t => {
    const f = fixture(t); f.receipt('2.0.18', f.binary);
    const {api} = virtualPolicy(f, {env: {SETUP_OPENCODE_HASHED: '/foreign/opencode'}});
    await assert.rejects(api.install(f.options), error => {
        assert.equal(api.failureResult(error), 'opencode-cli:policy-failed:setup-selection:command-conflict');
        return true;
    });
    assert.equal(f.probes.length, 0);
    assert.deepEqual(fs.readFileSync(f.dest), f.binary);
});
test('fresh native fish loads the private profile and rejects aliases, functions and shadowing without running commands', {skip: !fs.existsSync('/usr/bin/fish')}, async t => {
    const f = fixture(t), config = path.join(f.home, '.config/fish/config.fish');
    fs.mkdirSync(path.dirname(config), {recursive: true});
    const foreign = path.join(f.home, 'foreign/opencode');
    fs.mkdirSync(path.dirname(foreign));
    fs.writeFileSync(foreign, '#!/bin/sh\necho UNEXPECTED_EXECUTION > "$HOME/executed"\n', {mode: 0o700});
    f.shellBoundary = (file, args, options) => nativeExecFileSync(file, args, options);
    const {api} = virtualPolicy(f, {env: {SETUP_OPENCODE_SHELL: '/usr/bin/fish', HOME: f.home,
        XDG_CONFIG_HOME: path.join(f.home, '.config'), XDG_DATA_HOME: path.join(f.home, '.data'),
        XDG_CACHE_HOME: path.join(f.home, '.cache'), XDG_STATE_HOME: path.join(f.home, '.state'),
        XDG_DATA_DIRS: path.join(f.home, '.data'), FISH_UNIT_TESTS_RUNNING: '1', TERM: 'dumb'}});
    fs.writeFileSync(config, 'set -gx PATH "$HOME/.local/bin" "$HOME/foreign" $PATH\n' +
        'if status is-interactive; printf "Welcome SECRET banner\\n/foreign/opencode\\n"; end\n');
    assert.equal(await api.install(f.options), 'installed');
    f.options.commands = [f.dest];
    assert.equal(await api.install(f.options), 'current');
    const receipt = path.join(path.dirname(f.dest), '.setup-opencode-cli.json'), before = fs.readFileSync(receipt);
    for (const profile of [
        'set -gx PATH "$HOME/.local/bin" $PATH\nalias opencode "echo SECRET"\n',
        'set -gx PATH "$HOME/.local/bin" $PATH\nfunction opencode; echo SECRET; end\n',
        'set -gx PATH "$HOME/foreign" "$HOME/.local/bin" $PATH\n',
        'set -gx PATH "$HOME/.local/bin" $PATH\nif status is-interactive; alias opencode "echo SECRET"; end\n',
        'set -gx PATH "$HOME/.local/bin" $PATH\nif status is-interactive; function opencode; echo SECRET; end; end\n',
        'set -gx PATH "$HOME/.local/bin" $PATH\nif status is-interactive; set -gx PATH "$HOME/foreign" $PATH; end\n',
    ]) {
        fs.writeFileSync(config, profile);
        await assert.rejects(api.install(f.options), error => {
            assert.equal(api.failureResult(error), 'opencode-cli:policy-failed:fresh-shell-selection:command-conflict'); return true;
        });
        assert.deepEqual(fs.readFileSync(receipt), before);
        assert.equal(fs.existsSync(path.join(f.home, 'executed')), false);
        assert.equal(fs.readFileSync(config, 'utf8'), profile);
    }
});
for (const kind of ['nonexecutable-file', 'directory']) test(`native shells skip earlier foreign ${kind} during installation and repeated selection`, {skip: !fs.existsSync('/usr/bin/fish')}, async t => {
    const f = fixture(t), foreign = fs.mkdtempSync(path.join(os.tmpdir(), 'opencode-noncommand-'));
    t.after(() => fs.rmSync(foreign, {recursive: true, force: true}));
    const noncommand = path.join(foreign, 'opencode');
    if (kind === 'directory') fs.mkdirSync(noncommand);
    else fs.writeFileSync(noncommand, 'INERT foreign non-command', {mode: 0o644});
    const before = fs.lstatSync(noncommand);
    f.options.commands = [noncommand];
    f.options.path = [foreign, path.dirname(f.dest), '/usr/bin', '/bin'].join(path.delimiter);
    const config = path.join(f.home, '.config/fish/config.fish');
    fs.mkdirSync(path.dirname(config), {recursive: true});
    fs.writeFileSync(config, `set -gx PATH '${foreign}' "$HOME/.local/bin" /usr/bin /bin\n`);
    f.shellBoundary = (file, args, options) => nativeExecFileSync(file, args, options);
    const {api} = virtualPolicy(f, {env: {SETUP_OPENCODE_SHELL: '/usr/bin/fish', HOME: f.home,
        XDG_CONFIG_HOME: path.join(f.home, '.config'), XDG_DATA_HOME: path.join(f.home, '.data'),
        XDG_CACHE_HOME: path.join(f.home, '.cache'), XDG_STATE_HOME: path.join(f.home, '.state'),
        XDG_DATA_DIRS: path.join(f.home, '.data'), FISH_UNIT_TESTS_RUNNING: '1', TERM: 'dumb'}}, {
        'node:fs': new Proxy(fs, {get(object, key) {
            if (key === 'lstatSync') return file => {
                const st = fs.lstatSync(file);
                if (file === foreign || file === noncommand) st.uid = process.getuid() + 1;
                if (foreign.startsWith(file + path.sep)) st.mode &= ~0o022;
                return st;
            };
            return object[key];
        }}),
    });
    f.receipt('2.0.18', f.binary);
    f.options.commands.push(noncommand);
    assert.equal(nativeExecFileSync('/bin/bash', ['--noprofile', '--norc', '-c', 'command -v opencode'],
        {cwd: f.home, env: {HOME: f.home, PATH: f.options.path}, encoding: 'utf8'}).trim(), f.dest);
    assert.equal(await api.install(f.options), 'current');
    fs.unlinkSync(f.dest); fs.unlinkSync(path.join(path.dirname(f.dest), '.setup-opencode-cli.json'));
    f.options.commands = [noncommand];
    assert.equal(await api.install(f.options), 'installed');
    const after = fs.lstatSync(noncommand);
    for (const field of ['ino', 'mode', 'mtimeMs', 'size']) assert.equal(after[field], before[field]);
    if (kind === 'nonexecutable-file') assert.equal(fs.readFileSync(noncommand, 'utf8'), 'INERT foreign non-command');
});
test('unverified fresh-shell evidence is bounded, secret-safe and never accepted for current or newer copies', async t => {
    for (const release of ['2.0.18', '3.0.0']) {
        const f = fixture(t), bytes = f.publish('@opencode/cli-linux-x64-baseline', release);
        f.receipt(release, bytes);
        const {api} = virtualPolicy(f);
        for (const output of ['', 'SECRET\n' + f.dest + '\n', f.dest + '\nSECRET', f.dest + '\n\n']) {
            f.shellBoundary = () => Buffer.from(output);
            await assert.rejects(api.install(f.options), error => {
                assert.equal(api.failureResult(error), 'opencode-cli:policy-failed:fresh-shell-selection:selection-unverified'); return true;
            });
        }
        f.shellBoundary = () => { throw Object.assign(new Error('SECRET shell stderr'), {status: 3}); };
        await assert.rejects(api.install(f.options), error => {
            assert.equal(api.failureResult(error), 'opencode-cli:policy-failed:fresh-shell-selection:selection-unverified'); return true;
        });
        assert.deepEqual(fs.readFileSync(f.dest), bytes);
        assert.equal(f.probes.length, 0);
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
for (const manager of ['npm', 'bun', 'mise']) test(`${manager} group-writable native-copy/wrapper route migrates only the command, without lifecycle scripts`, async t => {
    const f = fixture(t);
    const packagePaths = {npm: '.local/lib/node_modules/opencode-ai', bun: '.bun/install/global/node_modules/opencode-ai',
        mise: '.local/share/mise/installs/node/24.20.0/lib/node_modules/opencode-ai'};
    const commandPaths = {npm: '.local/bin/opencode', bun: '.bun/bin/opencode', mise: '.local/share/mise/installs/node/24.20.0/bin/opencode'};
    const root = path.join(f.home, packagePaths[manager]);
    fs.mkdirSync(path.join(root, 'bin'), {recursive: true});
    fs.writeFileSync(path.join(root, 'package.json'), '{"name":"opencode-ai","version":"1.2.3"}');
    fs.writeFileSync(path.join(root, 'bin/opencode'), 'INERT wrapper');
    fs.writeFileSync(path.join(root, 'bin/.opencode'), 'INERT official 1.2.3');
    f.publish('opencode-ai', '1.2.3', 'INERT wrapper');
    f.publish('opencode-linux-x64-baseline', '1.2.3');
    const command = path.join(f.home, commandPaths[manager]);
    fs.mkdirSync(path.dirname(command), {recursive: true}); fs.symlinkSync(path.join(root, 'bin/opencode'), command);
    const directories = new Set();
    for (const leaf of [path.join(root, 'bin'), path.dirname(command), path.dirname(f.dest)]) {
        for (let current = leaf; current.startsWith(f.home); current = path.dirname(current)) directories.add(current);
    }
    for (const directory of directories) fs.chmodSync(directory, 0o2775);
    const snapshot = () => [...directories].map(directory => {
        const s = fs.lstatSync(directory); return [directory, s.uid, s.gid, s.mode, s.dev, s.ino];
    });
    const before = snapshot();
    const manifest = path.join(root, 'package.json'), beforeManifest = fs.readFileSync(manifest);
    f.options.commands.push(command);
    assert.equal(await policy.install(f.options), 'migrated');
    f.options.commands = [f.dest];
    assert.equal(await policy.install(f.options), 'current');
    assert.deepEqual(snapshot(), before);
    assert.deepEqual(fs.readFileSync(manifest), beforeManifest);
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
test('original selection failure survives a failed cleanup with controlled recovery diagnostics', async t => {
    const f = fixture(t);
    f.shellBoundary = () => Buffer.from('/SECRET/private/opencode\n');
    const remove = fs.rmSync;
    const {api} = virtualPolicy(f, {}, {'node:fs': new Proxy(fs, {get(object, key) {
        if (key === 'rmSync') return file => {
            if (path.basename(file).startsWith('.setup-opencode-')) throw new Error('SECRET cleanup exception');
            return remove(file, {recursive: true, force: true});
        };
        return object[key];
    }})});
    await assert.rejects(api.install(f.options), error => {
        assert.equal(api.failureResult(error), 'opencode-cli:recovery-required:policy-failed:fresh-shell-selection:command-conflict');
        return true;
    });
    assert.equal(fs.existsSync(f.dest), false);
    assert.ok(fs.existsSync(path.join(path.dirname(f.dest), '.setup-opencode-cli.lock')));
});
test('current-copy probe failure survives temporary cleanup failure', async t => {
    const f = fixture(t); f.receipt('2.0.18', f.binary);
    const leftovers = [];
    const {api} = virtualPolicy(f, {}, {
        'node:child_process': {execFileSync: () => { throw new Error('SECRET probe'); }},
        'node:fs': new Proxy(fs, {get(object, key) {
            if (key === 'rmSync') return file => { leftovers.push(file); throw new Error('SECRET cleanup'); };
            return object[key];
        }}),
    });
    t.after(() => { for (const file of leftovers) fs.rmSync(file, {recursive: true, force: true}); });
    await assert.rejects(api.install({...f.options, probe: undefined}), error => {
        assert.equal(api.failureResult(error), 'opencode-cli:recovery-required:policy-failed:installation:version-probe'); return true;
    });
    assert.deepEqual(fs.readFileSync(f.dest), f.binary);
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
for (const cause of ['world-directory', 'foreign-directory', 'root-directory', 'root-account', 'file-ancestor', 'link-ancestor',
    'linked-command', 'group-command', 'group-receipt', 'inspection']) test(`ordinary directory policy retains ${cause} refusal`, async t => {
    const f = fixture(t), directory = path.dirname(f.dest);
    f.receipt('2.0.18', f.binary);
    fs.chmodSync(f.home, 0o775); fs.chmodSync(path.join(f.home, '.local'), 0o2775); fs.chmodSync(directory, 0o775);
    const receipt = path.join(directory, '.setup-opencode-cli.json'), overrides = {};
    if (cause === 'world-directory') fs.chmodSync(directory, 0o777);
    if (cause === 'foreign-directory') overrides.uid = process.getuid() + 1;
    if (cause === 'root-directory' || cause === 'root-account') overrides.uid = 0;
    if (cause === 'file-ancestor') overrides.mode = 0o100775;
    if (cause === 'link-ancestor') overrides.mode = 0o120775;
    if (cause === 'linked-command') { fs.renameSync(f.dest, f.dest + '-saved'); fs.symlinkSync('opencode-saved', f.dest); }
    if (cause === 'group-command') fs.chmodSync(f.dest, 0o775);
    if (cause === 'group-receipt') fs.chmodSync(receipt, 0o664);
    const {api} = virtualPolicy(f, cause === 'root-account' ? {getuid: () => 0} : {}, {'node:fs': new Proxy(fs, {get(object, key) {
        if (key === 'lstatSync') return file => {
            if (file === directory && cause === 'inspection') throw Object.assign(new Error('SECRET failed stat'), {code: 'EACCES'});
            const info = fs.lstatSync(file);
            if (file === directory) Object.assign(info, overrides);
            if (cause === 'root-account') info.uid = 0;
            return info;
        };
        return object[key];
    }})});
    const contents = fs.readFileSync(receipt);
    await assert.rejects(api.install(f.options), error => {
        assert.equal(api.failureResult(error), 'opencode-cli:policy-failed:installation:' + (cause === 'inspection' ? 'native-EACCES' : 'unsafe-path'));
        return true;
    });
    assert.equal(f.probes.length, 0);
    assert.deepEqual(fs.readFileSync(receipt), contents);
    assert.deepEqual(fs.readFileSync(f.dest), f.binary);
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
function virtualPolicy(f, overrides = {}, modules = {}, log = () => assert.fail('unexpected output'), globals = {}) {
    const vm = require('node:vm');
    const mapped = value => typeof value === 'string' && (value === '/opt' || value.startsWith('/opt/')) ? path.join(f.home, 'virtual-opt', value.slice(4)) : value;
    const proxy = new Proxy(fs, {get(object, key) {
        if (typeof object[key] !== 'function') return object[key];
        return (...args) => object[key](...args.map(mapped));
    }});
    const module = {exports: {}};
    const fakeProcess = {platform: 'linux', env: {}, getuid: process.getuid, report: process.report, argv: ['node', 'fixture'], ...overrides};
    fakeProcess.env = {SETUP_OPENCODE_SHELL: '/fixture/fish', ...fakeProcess.env};
    const native = modules['node:child_process'] || require('node:child_process');
    const childProcess = {...native, execFileSync: (file, ...args) => file === fakeProcess.env.SETUP_OPENCODE_SHELL
        ? selectionOutput(file, args[0], f.shellBoundary(file, ...args)) : native.execFileSync(file, ...args)};
    vm.runInNewContext(fs.readFileSync(require.resolve('../lib/opencode-cli.cjs'), 'utf8'), {
        require: name => name === 'node:child_process' ? childProcess : modules[name] || (name === 'node:fs' ? proxy : require(name)), module, process: fakeProcess,
        Buffer, URL, setTimeout, clearTimeout, console: {log, error: () => assert.fail('unexpected output')}, ...globals,
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
test('real discovery uses native Windows delimiters, empty fields and absolute forms', t => {
    const f = fixture(t), absent = () => { throw Object.assign(new Error('PRIVATE_FS_SECRET'), {code: 'ENOENT'}); };
    const {api} = virtualPolicy(f, {platform: 'win32'}, {'node:path': path.win32, 'node:fs': {lstatSync: absent}});
    const home = 'C:\\Users\\fixture';
    for (const PATH of [undefined, '', ';', ';;C:\\bin;', '\\\\server\\share;C:/bin;\\rooted']) {
        assert.deepEqual(Array.from(api.commands(home, {HOME: home, PATH})), []);
    }
    for (const [PATH, index] of [[';;relative_SECRET', 3], ['C:\\bin;;.', 3], ['C:\\bin;%VARIABLE_SECRET%\\bin', 2], ['C:relative_SECRET', 1]]) {
        assert.throws(() => api.commands(home, {HOME: home, PATH}), error => {
            assert.equal(api.failureResult(error), `opencode-cli:policy-failed:installation:relative-path:command-discovery:${index}:relative`);
            return true;
        });
    }
});
test('real discovery bounds the canonical index without accepting an unsafe oversized PATH', t => {
    const f = fixture(t), {api} = virtualPolicy(f);
    for (const [PATH, expected] of [
        [Array(999998).fill('/absolute').join(':') + ':', 'opencode-cli:policy-failed:installation:relative-path:command-discovery:999999:empty'],
        [Array(999999).fill('/absolute').join(':') + ':SECRET', 'opencode-cli:policy-failed:installation:relative-path'],
    ]) assert.throws(() => api.commands(f.home, {HOME: f.home, PATH}), error => {
        assert.equal(api.failureResult(error), expected); return true;
    });
});
test('diagnostic construction or lookup failure retains the real installation refusal', async t => {
    for (const method of ['set', 'get']) {
        const f = fixture(t);
        class BrokenEvidence extends WeakMap { [method]() { throw new Error('DIAGNOSTIC_SECRET'); } }
        const {api} = virtualPolicy(f, {env: {PATH: 'PATH_SECRET'}}, {}, undefined, {WeakMap: BrokenEvidence});
        await assert.rejects(api.install({...f.options, commands: undefined}), error => {
            assert.equal(api.failureResult(error), 'opencode-cli:policy-failed:installation:relative-path'); return true;
        });
        assert.deepEqual(fs.readdirSync(path.dirname(f.dest)), []);
        assert.equal(f.probes.length, 0);
    }
});
test('forged evidence and hostile exceptions never become trusted PATH diagnostics', async t => {
    const f = fixture(t), {api} = virtualPolicy(f, {env: {PATH: 'PATH_SECRET'}});
    let real;
    await assert.rejects(api.install({...f.options, commands: undefined}), error => { real = error; return true; });
    const fields = {operation: 'installation', reason: 'relative-path', boundary: 'command-discovery', index: 2, kind: 'relative'};
    const revoked = Proxy.revocable({}, {}); revoked.revoke();
    for (const error of [fields, Object.assign(Object.create(Object.getPrototypeOf(real)), fields),
        {message: 'recovery-required'}, {get message() { throw new Error('GETTER_SECRET'); }}, revoked.proxy]) {
        assert.equal(api.failureResult(error), 'opencode-cli:failed');
    }
    await assert.rejects(api.install({...f.options, commands: ['SECRET/relative/opencode']}), error => {
        error.context = fields;
        assert.equal(api.failureResult(error), 'opencode-cli:policy-failed:installation:relative-path'); return true;
    });
    assert.equal(api.failureResult(real), 'opencode-cli:policy-failed:installation:relative-path:command-discovery:1:relative');
    assert.equal(f.probes.length, 0);
});
test('real version probe accepts exact bare and official named lines in isolation', t => {
    const f = fixture(t); let observed, output;
    const {api} = virtualPolicy(f, {env: {OPENCODE_API_KEY: 'fixture-secret', OPENCODE_CONFIG: '/fixture/config', NODE_OPTIONS: '--invalid'}},
        {'node:child_process': {execFileSync: (file, args, options) => { observed = {file, args, options}; return Buffer.from(output); }}});
    for (output of ['2.0.21', '2.0.21\n', '2.0.21\r\n', 'opencode v2.0.21', 'opencode v2.0.21\n', 'opencode v2.0.21\r\n', '  opencode v2.0.21  \n']) {
        api.probe(f.dest, '2.0.21', f.home);
        assert.deepEqual(Array.from(observed.args), ['--version']);
        assert.ok(observed.options.cwd.startsWith(f.home));
        for (const name of ['HOME', 'USERPROFILE', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME',
            'APPDATA', 'LOCALAPPDATA', 'TMPDIR', 'TMP', 'TEMP']) assert.equal(observed.options.env[name], observed.options.cwd);
        for (const name of ['OPENCODE_API_KEY', 'OPENCODE_CONFIG', 'NODE_OPTIONS']) assert.equal(observed.options.env[name], undefined);
        assert.equal(observed.options.env.PATH, path.dirname(f.dest));
        assert.equal(observed.options.env.NO_COLOR, '1');
        assert.equal(observed.options.timeout, 20000);
        assert.equal(observed.options.maxBuffer, 1024);
        assert.deepEqual(Array.from(observed.options.stdio), ['ignore', 'pipe', 'ignore']);
        assert.equal(observed.options.windowsHide, true);
    }
});
test('real version probe rejects all extra output and failed processes without leaking it', t => {
    const f = fixture(t); let output, failure;
    const {api} = virtualPolicy(f, {}, {'node:child_process': {execFileSync: () => {
        if (failure) throw Object.assign(new Error('PRIVATE-SENTINEL'), {stdout: Buffer.from('opencode v2.0.21\n'), ...failure});
        return Buffer.from(output);
    }}});
    const rejected = () => assert.throws(() => api.probe(f.dest, '2.0.21', f.home), error => {
        assert.equal(api.failureResult(error), 'opencode-cli:policy-failed:installation:version-probe'); return true;
    });
    for (output of ['', '2.0.20', 'opencode v2.0.20', '2.0.21-beta', '2.0.21+build', 'opencode v2.0.21-beta',
        'opencode v2.0.21+build', 'other v2.0.21', 'opencode 2.0.21', 'v2.0.21', 'OpenCode v2.0.21',
        'opencode v2.0.21\nPRIVATE-SENTINEL', 'PRIVATE-SENTINEL\n2.0.21', '2.0.21\n2.0.21',
        '\u001b[1mopencode v2.0.21\u001b[0m', 'opencode  v2.0.21']) rejected();
    for (failure of [{status: 1}, {code: 'ETIMEDOUT'}, {signal: 'SIGTERM'}, {code: 'ENOBUFS'}]) rejected();
});
for (const output of ['2.0.21\n', 'opencode v2.0.21\r\n']) test(`verified staged, promoted and current commands accept ${JSON.stringify(output)}`, async t => {
    const f = fixture(t), bytes = f.publish('@opencode/cli-linux-x64-baseline', '2.0.21');
    f.setLatest({version: '2.0.21'});
    const probed = [];
    const {api} = virtualPolicy(f, {}, {'node:child_process': {execFileSync: file => {
        assert.deepEqual(fs.readFileSync(file), bytes); probed.push(file); return Buffer.from(output);
    }}});
    const options = {...f.options, probe: undefined};
    assert.equal(await api.install(options), 'installed');
    assert.equal(probed.length, 2);
    assert.notEqual(probed[0], f.dest); assert.equal(probed[1], f.dest);
    options.commands = [f.dest];
    assert.equal(await api.install(options), 'current');
    assert.equal(probed.length, 3); assert.equal(probed[2], f.dest);
    fs.writeFileSync(f.dest, 'INERT custom bytes');
    await assert.rejects(api.install(options));
    assert.equal(probed.length, 3);
});
for (const phase of ['staged', 'promoted']) for (const failedProcess of [false, true]) {
    test(`real ${phase} probe ${failedProcess ? 'process' : 'output'} failure preserves prior command and receipt`, async t => {
        const f = fixture(t), previous = f.publish('@opencode/cli-linux-x64-baseline', '2.0.10');
        f.receipt('2.0.10', previous);
        const bytes = f.publish('@opencode/cli-linux-x64-baseline', '2.0.21'); f.setLatest({version: '2.0.21'});
        const receipt = path.join(path.dirname(f.dest), '.setup-opencode-cli.json'), before = fs.readFileSync(receipt);
        let calls = 0;
        const {api} = virtualPolicy(f, {}, {'node:child_process': {execFileSync: file => {
            assert.deepEqual(fs.readFileSync(file), bytes);
            if (++calls === (phase === 'staged' ? 1 : 2)) {
                if (failedProcess) throw Object.assign(new Error('PRIVATE-SENTINEL'), {status: 1, stdout: Buffer.from('opencode v2.0.21')});
                return Buffer.from('opencode v2.0.20');
            }
            return Buffer.from('opencode v2.0.21');
        }}});
        await assert.rejects(api.install({...f.options, probe: undefined}), /version-probe/);
        assert.equal(calls, phase === 'staged' ? 1 : 2);
        assert.deepEqual(fs.readFileSync(f.dest), previous); assert.deepEqual(fs.readFileSync(receipt), before);
    });
}
function homebrewFixture(t, platform = 'linux', prefix = '/home/linuxbrew/.linuxbrew', release = '1.18.33', revision = '') {
    const f = fixture(t), calls = [], observed = [];
    const keg = release + revision;
    const command = prefix + '/bin/opencode', cellar = prefix + '/Cellar/opencode/' + keg;
    const logical = file => typeof file === 'string' && (file === '/' || file === '/home' || file === '/opt' ||
        file.startsWith('/opt/homebrew') || file.startsWith('/home/linuxbrew') || /^\/(etc|proc|usr)(\/|$)/.test(file));
    const mapped = file => logical(file) ? path.join(f.home, 'system', file.slice(1)) : file;
    const uid = process.getuid(), gid = process.getgid();
    const privacySystem = file => /^\/(etc|proc|usr)(\/|$)/.test(file) && file !== '/usr' &&
        file !== '/usr/local' && !file.startsWith('/usr/local/');
    function put(file, text, mode = 0o644) {
        fs.mkdirSync(path.dirname(mapped(file)), {recursive: true});
        fs.writeFileSync(mapped(file), text); fs.chmodSync(mapped(file), mode);
    }
    put('/etc/nsswitch.conf', 'passwd: files systemd\ngroup: files systemd\ninitgroups: files systemd\n');
    put('/etc/passwd', `account:x:${uid}:${gid}:fixture:/fixture:/bin/false\nother:x:${uid+1}:${gid+1}:fixture:/other:/bin/false\n`);
    put('/etc/group', `account:x:${gid}:\nother:x:${gid+1}:\n`);
    put('/proc/self/mountinfo', '19 20 0:21 / /proc rw,nosuid,nodev,noexec - proc proc rw\n');
    put('/proc/123/task/123/status', `Uid:\t${uid+1} ${uid+1} ${uid+1} ${uid+1}\nGid:\t${gid+1} ${gid+1} ${gid+1} ${gid+1}\nGroups:\t${gid+1}\n`);
    put('/proc/123/task/123/stat', '123 (inert fixture) S ' + Array(18).fill('0').join(' ') + ' 12345\n');
    put('/proc/456/task/456/status', `Uid:\t${uid+1} ${uid+1} ${uid+1} ${uid+1}\nGid:\t${gid+1} ${gid+1} ${gid+1} ${gid+1}\nGroups:\t${gid+1}\n`);
    put('/proc/456/task/456/stat', '456 (stable fixture) S ' + Array(18).fill('0').join(' ') + ' 23456\n');
    put('/usr/bin/python3.12', 'INERT python marker', 0o755);
    fs.symlinkSync('python3.12', mapped('/usr/bin/python3'));
    put(cellar + '/bin/opencode', f.publish('opencode-linux-x64-baseline', release), 0o555);
    put(cellar + '/INSTALL_RECEIPT.json', '{"source":{"tap":"anomalyco/tap"}}', 0o664);
    fs.mkdirSync(mapped(prefix + '/bin'), {recursive: true});
    fs.symlinkSync('../Cellar/opencode/' + keg + '/bin/opencode', mapped(command));
    function modes(dir) {
        fs.chmodSync(dir, 0o755);
        for (const name of fs.readdirSync(dir)) if (fs.lstatSync(path.join(dir, name)).isDirectory()) modes(path.join(dir, name));
    }
    modes(mapped('/'));
    for (const dir of [prefix + '/Cellar', prefix + '/Cellar/opencode', cellar, cellar + '/bin']) fs.chmodSync(mapped(dir), 0o775);
    f.statOverrides = new Map();
    const proxy = new Proxy(fs, {get(object, key) {
        if (typeof object[key] !== 'function') return object[key];
        return (...args) => {
            if (logical(args[0])) {
                observed.push([key, args[0]]);
                assert.ok(!privacySystem(args[0]), 'privacy-proof system access forbidden');
                assert.ok(!['chmodSync', 'chownSync', 'writeFileSync', 'unlinkSync', 'rmSync', 'mkdirSync', 'linkSync', 'symlinkSync'].includes(key), 'Homebrew/system writes forbidden except command quarantine/restore');
                if (key === 'openSync') assert.equal(args[1] & (fs.constants.O_WRONLY | fs.constants.O_RDWR | fs.constants.O_CREAT | fs.constants.O_TRUNC), 0);
                if (key === 'renameSync') assert.ok(args[0] === command || args[0].startsWith(prefix + '/bin/.opencode-setup-recovery-'));
            }
            const value = object[key](...args.map(mapped));
            if (key === 'lstatSync' && logical(args[0]) && (args[0] === '/' || args[0] === '/home' || args[0] === '/opt' || args[0] === '/usr' || privacySystem(args[0]))) value.uid = 0;
            if (key === 'lstatSync' && f.statOverrides.has(args[0])) Object.assign(value, f.statOverrides.get(args[0]));
            if (key === 'renameSync' && args[0] === command && f.afterQuarantine) f.afterQuarantine(args[1]);
            return value;
        };
    }});
    const native = new Proxy({}, {get: (_, operation) => (file, args, options) => {
        calls.push({operation, file, args, options});
        assert.equal(operation, 'execFileSync', 'privacy-proof external operations forbidden');
        assert.ok(file.startsWith(path.dirname(f.dest) + path.sep), 'only staged/promoted commands may be probed');
        assert.deepEqual(Array.from(args), ['--version']);
        assert.deepEqual(fs.readFileSync(file), f.binary, 'official bytes precede the inert probe');
        assert.ok(options.cwd.startsWith(f.home) || options.cwd.startsWith(os.tmpdir() + path.sep));
        assert.equal(options.env.HOME, options.cwd);
        assert.equal(options.env.PATH, path.dirname(file));
        f.probes.push({file, release: '2.0.18'});
        if (f.duringProbe) f.duringProbe(f.probes.length);
        return Buffer.from('opencode v2.0.18\n');
    }});
    const forbidden = () => assert.fail('account/group inventory forbidden');
    const {api} = virtualPolicy(f, {platform, getgid: forbidden, getgroups: forbidden}, {
        'node:fs': proxy, 'node:child_process': native, 'node:os': {...os, userInfo: forbidden},
    });
    f.options.commands = [command];
    f.options.probe = undefined;
    t.after(() => {
        assert.ok(calls.every(call => call.operation === 'execFileSync'), 'privacy-proof external operations forbidden');
        assert.ok(observed.every(([, file]) => !privacySystem(file)), 'privacy-proof system access forbidden');
    });
    return Object.assign(f, {api, command, prefix, cellar, mapped, put, calls, observed});
}
test('recognized Homebrew migration accepts account-owned ancestors outside its prefix without privacy proofs', async t => {
    const f = homebrewFixture(t), boundary = '/home/linuxbrew';
    fs.chmodSync(f.mapped(boundary), 0o2775);
    for (const directory of [f.home, path.join(f.home, '.local'), path.dirname(f.dest)]) fs.chmodSync(directory, 0o775);
    const before = fs.lstatSync(f.mapped(boundary));
    for (const dir of ['/etc', '/proc', '/usr']) fs.rmSync(f.mapped(dir), {recursive: true});
    assert.equal(await f.api.install(f.options), 'migrated');
    f.options.commands = [f.dest];
    assert.equal(await f.api.install(f.options), 'current');
    const after = fs.lstatSync(f.mapped(boundary));
    for (const key of ['uid', 'gid', 'mode', 'dev', 'ino']) assert.equal(after[key], before[key]);
    assert.deepEqual(fs.readFileSync(f.dest), f.binary);
});
test('accepted Homebrew ancestor mode changes still invalidate migration evidence', async t => {
    const f = homebrewFixture(t), boundary = f.mapped('/home/linuxbrew');
    fs.chmodSync(boundary, 0o775);
    f.duringProbe = count => { if (count === 1) fs.chmodSync(boundary, 0o2775); };
    await assert.rejects(f.api.install(f.options), error => {
        assert.equal(f.api.failureResult(error), 'opencode-cli:policy-failed:homebrew-preflight:brew-snapshot-changed'); return true;
    });
    assert.equal(fs.statSync(boundary).mode & 0o7777, 0o2775);
    assert.equal(fs.readlinkSync(f.mapped(f.command)), '../Cellar/opencode/1.18.33/bin/opencode');
    assert.equal(fs.existsSync(f.dest), false);
});
test('verified newer account-owned Homebrew command is preserved with native bytes and route trust intact', async t => {
    const f = homebrewFixture(t), newer = f.prefix + '/Cellar/opencode/3.0.0';
    const bytes = f.publish('@opencode/cli-linux-x64-baseline', '3.0.0');
    f.put(newer + '/bin/opencode', bytes, 0o555);
    f.put(newer + '/INSTALL_RECEIPT.json', '{"source":{"tap":"anomalyco/tap"}}', 0o664);
    fs.unlinkSync(f.mapped(f.command)); fs.symlinkSync('../Cellar/opencode/3.0.0/bin/opencode', f.mapped(f.command));
    f.options.path = f.prefix + '/bin'; f.shellSelection = f.command;
    const before = fs.lstatSync(f.mapped(f.command));
    assert.equal(await f.api.install(f.options), 'newer');
    assert.equal(f.probes.length, 0);
    assert.equal(fs.lstatSync(f.mapped(f.command)).ino, before.ino);
    assert.equal(fs.readlinkSync(f.mapped(f.command)), '../Cellar/opencode/3.0.0/bin/opencode');
    assert.deepEqual(fs.readFileSync(f.mapped(newer + '/bin/opencode')), bytes);
    assert.deepEqual(fs.readdirSync(path.dirname(f.dest)), []);
    f.shellBoundary = () => {
        f.put(newer + '/INSTALL_RECEIPT.json', '{"source":{"tap":"custom/tap"}}', 0o664);
        return Buffer.from(f.command + '\n');
    };
    await assert.rejects(f.api.install(f.options), /brew-snapshot-changed/);
    assert.equal(fs.readFileSync(f.mapped(newer + '/INSTALL_RECEIPT.json'), 'utf8'), '{"source":{"tap":"custom/tap"}}');
    assert.equal(f.probes.length, 0);
});
test('lower-priority foreign Homebrew survives account-local install and repeated verification without inspection or execution', async t => {
    const f = homebrewFixture(t);
    f.statOverrides.set(f.prefix, {uid: process.getuid() + 1});
    f.statOverrides.set(f.command, {uid: process.getuid() + 1});
    f.options.path += path.delimiter + f.prefix + '/bin';
    const snapshot = () => {
        const walk = dir => fs.readdirSync(dir).sort().flatMap(name => {
            const file = path.join(dir, name), st = fs.lstatSync(file);
            return [[file, st.mode, st.ino, st.mtimeMs, st.isSymbolicLink() ? fs.readlinkSync(file) : st.isFile() ? fs.readFileSync(file) : null],
                ...(st.isDirectory() ? walk(file) : [])];
        });
        return walk(f.mapped(f.prefix));
    };
    f.put(f.prefix + '/bin/.opencode-setup-recovery-existing', 'foreign recovery');
    const before = snapshot();
    assert.equal(await f.api.install(f.options), 'installed');
    f.options.commands = [f.dest, f.command];
    assert.equal(await f.api.install(f.options), 'current');
    assert.deepEqual(snapshot(), before);
    assert.equal(f.calls.some(call => call.file.startsWith(f.prefix)), false);
    assert.equal(f.observed.some(([operation, file]) => file.startsWith(f.prefix + '/') &&
        !(operation === 'lstatSync' && file === f.command)), false, 'do not inspect beyond the foreign ownership boundary');
});
for (const state of ['upgrade', 'newer', 'owned-migration', 'pinned', 'custom', 'staged-failure', 'promoted-failure']) {
    test(`foreign commands remain untouched through account-local ${state}`, async t => {
        const f = homebrewFixture(t);
        f.statOverrides.set(f.prefix, {uid: process.getuid() + 1});
        const native = f.mapped(f.cellar + '/bin/opencode'), receipt = f.mapped(f.cellar + '/INSTALL_RECEIPT.json');
        const before = [fs.readFileSync(native), fs.readFileSync(receipt), fs.readlinkSync(f.mapped(f.command)), fs.lstatSync(receipt).mode];
        if (['upgrade', 'staged-failure', 'promoted-failure'].includes(state)) f.receipt('2.0.10', f.publish('@opencode/cli-linux-x64-baseline', '2.0.10'));
        if (state === 'newer') f.receipt('3.0.0', f.publish('@opencode/cli-linux-x64-baseline', '3.0.0'));
        if (state === 'pinned') f.receipt('2.0.18', f.binary, {pinned: true});
        if (state === 'owned-migration' || state === 'custom') f.legacy('.opencode/bin', state === 'custom' ? 'INERT custom' : 'INERT official 1.2.3');
        if (state === 'custom') fs.writeFileSync(f.options.commands.at(-1), 'unidentified custom');
        if (!f.options.commands.includes(f.command)) f.options.commands.push(f.command);
        f.options.path += path.delimiter + f.prefix + '/bin';
        f.duringProbe = count => { if ((state === 'staged-failure' && count === 1) || (state === 'promoted-failure' && count === 2)) throw new Error('inert probe refusal'); };
        if (['pinned', 'custom', 'staged-failure', 'promoted-failure'].includes(state)) await assert.rejects(f.api.install(f.options));
        else assert.equal(await f.api.install(f.options), state === 'newer' ? 'newer' : 'migrated');
        assert.deepEqual([fs.readFileSync(native), fs.readFileSync(receipt), fs.readlinkSync(f.mapped(f.command)), fs.lstatSync(receipt).mode], before);
        assert.equal(f.calls.some(call => call.file.startsWith(f.prefix)), false);
        assert.deepEqual(fs.readdirSync(f.mapped(f.prefix + '/bin')), ['opencode']);
    });
}
test('higher-priority foreign command cannot be hidden by account-local PATH membership', async t => {
    const f = homebrewFixture(t);
    f.statOverrides.set(f.prefix, {uid: process.getuid() + 1});
    f.options.path = f.prefix + '/bin' + path.delimiter + path.dirname(f.dest);
    await assert.rejects(f.api.install(f.options), error => {
        assert.equal(f.api.failureResult(error), 'opencode-cli:policy-failed:setup-selection:foreign-command');
        return true;
    });
    assert.equal(fs.existsSync(f.dest), false);
    assert.equal(fs.readlinkSync(f.mapped(f.command)), '../Cellar/opencode/1.18.33/bin/opencode');
    assert.equal(f.calls.some(call => call.file.startsWith(f.prefix)), false);
});
test('busy-system 0775/0664 Homebrew migration does not require a quiet process inventory', async t => {
    const f = homebrewFixture(t);
    const churn = () => {
        fs.rmSync(f.mapped('/proc/123'), {recursive: true, force: true});
        f.put('/proc/789/task/790/status', 'changing unrelated process');
    };
    f.duringProbe = churn; f.afterQuarantine = churn;
    const receipt = f.mapped(f.cellar + '/INSTALL_RECEIPT.json');
    const before = fs.statSync(receipt), contents = fs.readFileSync(receipt);
    assert.equal(await f.api.install(f.options), 'migrated');
    assert.deepEqual(fs.readFileSync(f.dest), f.binary);
    assert.equal(fs.existsSync(f.mapped(f.command)), false);
    assert.equal(fs.statSync(f.mapped(f.cellar + '/bin')).mode & 0o777, 0o775);
    const after = fs.statSync(receipt);
    assert.equal(after.mode & 0o777, 0o664); assert.equal(after.ino, before.ino); assert.equal(after.mtimeMs, before.mtimeMs);
    assert.deepEqual(fs.readFileSync(receipt), contents);
    assert.equal(f.probes.length, 2);
    f.options.commands = [f.dest];
    assert.equal(await f.api.install(f.options), 'current');
    assert.equal(f.probes.length, 3);
});
for (const state of ['service-primary', 'service-supplementary', 'stale-service-thread', 'nonprimary-path-group',
    'restricted-identity-provider', 'disappeared-process', 'disappeared-thread', 'unavailable-proof-dependencies']) {
    test(`0775/0664 Homebrew migration preserves stores and data with ${state}`, async t => {
        const f = homebrewFixture(t), uid = process.getuid(), gid = process.getgid();
        if (state === 'service-primary') f.put('/etc/passwd', `account:x:${uid}:${gid}:fixture:/a:/bin/false\nservice:x:${uid+1}:${gid}:fixture:/b:/bin/false\n`);
        if (state === 'service-supplementary') f.put('/etc/group', `account:x:${gid}:service\n`);
        if (state === 'stale-service-thread') f.put('/proc/123/task/124/status', `Uid: ${uid+1} ${uid+1} ${uid+1} ${uid+1}\nGid: 0 0 0 0\nGroups: ${gid}\n`);
        if (state === 'nonprimary-path-group') f.statOverrides.set(f.prefix + '/Cellar', {gid: gid+1});
        if (state === 'restricted-identity-provider') f.put('/etc/nsswitch.conf', 'passwd: sss\ngroup: sss\ninitgroups: sss\n');
        if (state === 'disappeared-process') fs.rmSync(f.mapped('/proc/123'), {recursive: true});
        if (state === 'disappeared-thread') fs.rmSync(f.mapped('/proc/123/task/123'), {recursive: true});
        if (state === 'unavailable-proof-dependencies') {
            for (const dir of ['/etc', '/proc', '/usr']) fs.rmSync(f.mapped(dir), {recursive: true});
        }
        const preserved = [f.mapped(f.cellar + '/bin/opencode'), f.mapped(f.cellar + '/INSTALL_RECEIPT.json')];
        for (const file of ['.config/opencode/config.json', '.local/share/opencode/auth.json', '.local/share/opencode/sessions', '.bashrc', 'project/opencode.json']) {
            const target = path.join(f.home, file);
            fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, 'INERT preserved data');
            preserved.push(target);
        }
        const snapshot = file => {
            const info = fs.lstatSync(file);
            return {bytes: fs.readFileSync(file), uid: info.uid, gid: info.gid, mode: info.mode, ino: info.ino, mtime: info.mtimeMs};
        };
        const before = preserved.map(snapshot);
        assert.equal(await f.api.install(f.options), 'migrated');
        assert.deepEqual(fs.readFileSync(f.dest), f.binary);
        assert.deepEqual(preserved.map(snapshot), before);
        assert.equal(fs.existsSync(f.mapped(f.command)), false);
        const backup = fs.readdirSync(f.mapped(f.prefix + '/bin')).find(name => name.startsWith('.opencode-setup-recovery-'));
        assert.equal(fs.readlinkSync(f.mapped(f.prefix + '/bin/' + backup)), '../Cellar/opencode/1.18.33/bin/opencode');
        assert.deepEqual(f.calls.map(call => call.operation), ['execFileSync', 'execFileSync']);
        f.options.commands = [f.dest];
        assert.equal(await f.api.install(f.options), 'current');
        assert.deepEqual(preserved.map(snapshot), before);
    });
}
for (const cause of ['world-write', 'root-group-write', 'foreign-owner', 'linked-ancestor']) {
    test(`Homebrew rejects ${cause} before mutation or unsafe descendant reads`, async t => {
        const f = homebrewFixture(t, 'linux', '/home/linuxbrew/.linuxbrew', '1.18.33', '_2'), boundary = f.prefix + '/Cellar';
        if (cause === 'world-write') fs.chmodSync(f.mapped(boundary), 0o777);
        if (cause === 'root-group-write') f.statOverrides.set(boundary, {uid: 0});
        if (cause === 'foreign-owner') f.statOverrides.set(boundary, {uid: process.getuid()+1});
        if (cause === 'linked-ancestor') {
            fs.renameSync(f.mapped(boundary), f.mapped(boundary + '-saved'));
            fs.symlinkSync('Cellar-saved', f.mapped(boundary));
        }
        const beforeLink = fs.readlinkSync(f.mapped(f.command));
        await assert.rejects(f.api.install(f.options), error => {
            assert.equal(f.api.failureResult(error), 'opencode-cli:policy-failed:homebrew-preflight:brew-path'); return true;
        });
        assert.equal(fs.readlinkSync(f.mapped(f.command)), beforeLink); assert.equal(f.probes.length, 0);
        assert.deepEqual(fs.readdirSync(path.dirname(f.dest)), []);
        assert.equal(f.observed.some(([, file]) => file.startsWith(boundary + '/')), false, 'do not inspect descendants of an untrusted boundary');
    });
}
test('ordinary directory acceptance leaves macOS Homebrew regular files strict', t => {
    const mac = homebrewFixture(t, 'darwin');
    assert.throws(() => mac.api.brewCopy(mac.command), /brew-path/); assert.equal(mac.calls.length, 0);
});
function darwinBrewDirectories(f) {
    return [f.prefix, f.prefix + '/bin', f.prefix + '/Cellar', f.prefix + '/Cellar/opencode',
        f.cellar, f.cellar + '/bin', f.prefix + '/var', f.prefix + '/var/homebrew', f.prefix + '/var/homebrew/pinned'];
}
function darwinHomebrewFixture(t, release = '1.18.33', revision = '', prefix = '/opt/homebrew') {
    const f = homebrewFixture(t, 'darwin', prefix, release, revision);
    f.put(prefix + '/var/homebrew/pinned/inert-sentinel', 'INERT unrelated pin');
    for (const dir of darwinBrewDirectories(f)) fs.chmodSync(f.mapped(dir), 0o775);
    fs.chmodSync(f.mapped(f.cellar + '/INSTALL_RECEIPT.json'), 0o644);
    f.options.target = prefix === '/usr/local' ? 'darwin-x64-baseline' : 'darwin-arm64';
    f.publish('opencode-' + f.options.target, release);
    f.publish('@opencode/cli-' + f.options.target, '2.0.18');
    return f;
}
test('owner Homebrew 1.18.30_2 capture migrates with group-writable bin Cellar and var ancestors', async t => {
    const f = darwinHomebrewFixture(t, '1.18.30', '_2');
    const writable = new Set([f.prefix + '/bin', f.prefix + '/Cellar', f.prefix + '/var', f.prefix + '/var/homebrew']);
    for (const dir of darwinBrewDirectories(f)) fs.chmodSync(f.mapped(dir), writable.has(dir) ? 0o775 : 0o755);
    fs.rmSync(f.mapped(f.prefix + '/var/homebrew/pinned'), {recursive: true});
    const preserved = [f.mapped(f.cellar + '/bin/opencode'), f.mapped(f.cellar + '/INSTALL_RECEIPT.json')];
    for (const file of ['.config/opencode/config.json', '.local/share/opencode/auth.json', '.bashrc', 'project/opencode.json']) {
        const target = path.join(f.home, file);
        fs.mkdirSync(path.dirname(target), {recursive: true}); fs.writeFileSync(target, 'INERT preserved data');
        preserved.push(target);
    }
    const snapshot = file => {
        const info = fs.lstatSync(file);
        return {bytes: fs.readFileSync(file), ino: info.ino, mode: info.mode, mtime: info.mtimeMs};
    };
    const before = preserved.map(snapshot);
    assert.equal(fs.readlinkSync(f.mapped(f.command)), '../Cellar/opencode/1.18.30_2/bin/opencode');
    assert.equal(await f.api.install(f.options), 'migrated');
    assert.deepEqual(fs.readFileSync(f.dest), f.binary);
    assert.deepEqual(preserved.map(snapshot), before);
    const backup = fs.readdirSync(f.mapped(f.prefix + '/bin')).find(name => name.startsWith('.opencode-setup-recovery-'));
    assert.equal(fs.readlinkSync(f.mapped(f.prefix + '/bin/' + backup)), '../Cellar/opencode/1.18.30_2/bin/opencode');
    f.options.commands = [f.dest];
    assert.equal(await f.api.install(f.options), 'current');
    assert.deepEqual(preserved.map(snapshot), before);
});
for (const route of ['darwin-arm', 'darwin-conventional', 'linux']) {
    for (const revision of ['', '_1', '_2', '_123', '_9007199254740991']) for (const absolute of [false, true]) {
        test(`${route} ${revision || 'unrevisioned'} ${absolute ? 'absolute' : 'relative'} Homebrew link migrates and repeats`, async t => {
            const f = route === 'linux' ? homebrewFixture(t, 'linux', '/home/linuxbrew/.linuxbrew', '1.18.30', revision)
                : darwinHomebrewFixture(t, '1.18.30', revision, route === 'darwin-arm' ? '/opt/homebrew' : '/usr/local');
            if (absolute) {
                fs.unlinkSync(f.mapped(f.command)); fs.symlinkSync(f.cellar + '/bin/opencode', f.mapped(f.command));
            }
            const receipt = f.mapped(f.cellar + '/INSTALL_RECEIPT.json'), before = fs.readFileSync(receipt);
            assert.equal(await f.api.install(f.options), 'migrated');
            assert.deepEqual(fs.readFileSync(f.dest), f.binary);
            assert.deepEqual(fs.readFileSync(receipt), before);
            f.options.commands = [f.dest];
            assert.equal(await f.api.install(f.options), 'current');
        });
    }
}
for (const route of ['darwin', 'linux']) test(`${route} verified newer revision-bearing release is preserved without probes`, async t => {
    const f = route === 'darwin' ? darwinHomebrewFixture(t, '3.0.0', '_12')
        : homebrewFixture(t, 'linux', '/home/linuxbrew/.linuxbrew', '3.0.0', '_12');
    f.publish('@opencode/cli-' + f.options.target, '3.0.0');
    f.options.path = f.prefix + '/bin'; f.shellSelection = f.command;
    const before = fs.readlinkSync(f.mapped(f.command));
    assert.equal(await f.api.install(f.options), 'newer');
    assert.equal(fs.readlinkSync(f.mapped(f.command)), before);
    assert.equal(f.probes.length, 0);
    assert.deepEqual(fs.readdirSync(path.dirname(f.dest)), []);
});
for (const [release, revision, reason] of [
    ...['_', '_0', '_01', '_+1', '_-1', '_abc', '_2_3', '_2-beta', '_2+build', '_9007199254740992']
        .map(revision => ['1.18.30', revision, 'brew-command']),
    ['01.18.30', '_2', 'version'], ['1.18', '_2', 'version'], ['1.18.30-beta', '_2', 'brew-command'],
    ['1.18.30+build', '_2', 'brew-command'],
]) test(`unsupported Homebrew keg ${release}${revision} fails before probe or promotion`, async t => {
    const f = darwinHomebrewFixture(t, release, revision), before = fs.readlinkSync(f.mapped(f.command));
    await assert.rejects(f.api.install(f.options), error => {
        assert.equal(f.api.failureResult(error), `opencode-cli:policy-failed:${reason === 'version' ? 'installation' : 'homebrew-preflight'}:${reason}`); return true;
    });
    assert.equal(fs.readlinkSync(f.mapped(f.command)), before);
    assert.equal(f.probes.length, 0);
    assert.deepEqual(fs.readdirSync(path.dirname(f.dest)), []);
});
for (const prefix of ['/opt/homebrew', '/usr/local']) {
    test(`Darwin ${prefix} account-owned group-writable directories permit verified migration and repeat without chmod`, async t => {
        const f = darwinHomebrewFixture(t, '1.18.30', '_2', prefix);
        const snapshot = () => darwinBrewDirectories(f).map(file => {
            const s = fs.lstatSync(f.mapped(file));
            return [file, s.dev, s.ino, s.uid, s.gid, s.mode];
        });
        const directories = snapshot();
        const receipt = f.mapped(f.cellar + '/INSTALL_RECEIPT.json'), before = fs.readFileSync(receipt);
        assert.equal(await f.api.install(f.options), 'migrated');
        assert.deepEqual(snapshot(), directories, 'no permission, owner or directory identity repair');
        assert.deepEqual(fs.readFileSync(receipt), before);
        assert.equal(fs.existsSync(f.mapped(f.command)), false);
        assert.deepEqual(fs.readFileSync(f.dest), f.binary);
        f.options.commands = [f.dest];
        assert.equal(await f.api.install(f.options), 'current');
        assert.deepEqual(snapshot(), directories);
    });
    test(`Darwin ${prefix} root-owned non-writable prefix remains valid with account-owned writable descendants`, async t => {
        const f = darwinHomebrewFixture(t, '1.18.30', '_2', prefix);
        fs.chmodSync(f.mapped(prefix), 0o755); f.statOverrides.set(prefix, {uid: 0});
        assert.equal(await f.api.install(f.options), 'migrated');
    });
    for (const relative of ['', '/bin', '/Cellar', '/Cellar/opencode', '/Cellar/opencode/1.18.33_2',
        '/Cellar/opencode/1.18.33_2/bin', '/var', '/var/homebrew', '/var/homebrew/pinned']) {
        for (const change of ['world-write', 'root-group-write', 'foreign-owner', 'linked-ancestor']) {
            test(`Darwin ${prefix}${relative} rejects ${change} before reading descendants`, t => {
                const f = darwinHomebrewFixture(t, '1.18.33', '_2', prefix), boundary = prefix + relative;
                if (change === 'world-write') fs.chmodSync(f.mapped(boundary), 0o777);
                if (change === 'root-group-write') f.statOverrides.set(boundary, {uid: 0});
                if (change === 'foreign-owner') f.statOverrides.set(boundary, {uid: process.getuid() + 1});
                if (change === 'linked-ancestor') {
                    fs.renameSync(f.mapped(boundary), f.mapped(boundary + '-saved'));
                    fs.symlinkSync(path.basename(boundary) + '-saved', f.mapped(boundary));
                }
                assert.throws(() => f.api.brewCopy(f.command), /brew-path/);
                assert.equal(f.observed.some(([, file]) => file.startsWith(boundary + '/')), false);
                assert.equal(f.calls.length, 0);
            });
        }
    }
    test(`Darwin ${prefix} does not accept group write on its system parent`, t => {
        const f = darwinHomebrewFixture(t, '1.18.33', '_2', prefix);
        fs.chmodSync(f.mapped(path.dirname(prefix)), 0o775);
        assert.throws(() => f.api.brewCopy(f.command), /brew-path/);
        assert.equal(f.observed.some(([, file]) => file.startsWith(prefix + '/')), false);
    });
}
for (const relative of ['/Cellar/opencode/1.18.33_2/bin/opencode',
    '/Cellar/opencode/1.18.33_2/INSTALL_RECEIPT.json']) {
    test(`Darwin directory allowance does not extend to group-writable files: ${relative}`, async t => {
        const f = darwinHomebrewFixture(t, '1.18.33', '_2'), boundary = f.prefix + relative;
        fs.chmodSync(f.mapped(boundary), fs.lstatSync(f.mapped(boundary)).mode | 0o020);
        await assert.rejects(f.api.install(f.options), error => {
            assert.equal(f.api.failureResult(error), 'opencode-cli:policy-failed:homebrew-preflight:brew-path'); return true;
        });
        assert.equal(f.observed.some(([operation, file]) => file.startsWith(boundary + '/') &&
            !(operation === 'lstatSync' && (file === f.command || f.command.startsWith(file + '/')))), false,
            'ownership-only command-route stats must not inspect a refused keg or receipt');
        assert.equal(f.calls.length, 0);
    });
}
test('Darwin directory allowance does not recognize lexical near matches or nested commands', t => {
    const f = darwinHomebrewFixture(t);
    for (const command of ['/opt/homebrew/bin-extra/opencode', '/opt/homebrew/binary/opencode',
        '/opt/homebrew/bin/child/opencode', '/opt/homebrew/bin//opencode', '/opt/homebrew/./bin/opencode',
        '/opt/homebrew/bin/../bin/opencode', '/opt/homebrew-other/bin/opencode']) {
        assert.equal(f.api.brewCopy(command), null, 'unrecognized route supplies no Homebrew trust');
    }
    assert.deepEqual(f.observed, []); assert.deepEqual(f.calls, []);
});
for (const [change, reason] of [['pin', 'pinned'], ['custom-tap', 'brew-origin'],
    ['custom-link', 'brew-command'], ['custom-bytes', 'unverified-copy']]) {
    test(`Darwin group-writable directories retain ${change} refusal before any probe or migration`, async t => {
        const f = darwinHomebrewFixture(t, '1.18.33', '_2');
        if (change === 'pin') f.put(f.prefix + '/var/homebrew/pinned/opencode', 'INERT pin');
        if (change === 'custom-tap') f.put(f.cellar + '/INSTALL_RECEIPT.json', '{"source":{"tap":"custom/tap"}}');
        if (change === 'custom-link') {
            fs.unlinkSync(f.mapped(f.command)); fs.symlinkSync('../custom/opencode', f.mapped(f.command));
        }
        if (change === 'custom-bytes') {
            fs.chmodSync(f.mapped(f.cellar + '/bin/opencode'), 0o755);
            f.put(f.cellar + '/bin/opencode', 'INERT custom bytes', 0o555);
        }
        const before = fs.readlinkSync(f.mapped(f.command));
        await assert.rejects(f.api.install(f.options), error => {
            const operation = reason.startsWith('brew-') ? 'homebrew-preflight' : 'installation';
            assert.equal(f.api.failureResult(error), `opencode-cli:policy-failed:${operation}:${reason}`); return true;
        });
        assert.equal(fs.readlinkSync(f.mapped(f.command)), before);
        assert.equal(fs.existsSync(f.dest), false); assert.equal(f.calls.length, 0);
        assert.equal(fs.statSync(f.mapped(f.prefix + '/bin')).mode & 0o777, 0o775);
    });
}
for (const relative of ['', '/bin', '/Cellar', '/Cellar/opencode', '/Cellar/opencode/1.18.33_2',
    '/Cellar/opencode/1.18.33_2/bin', '/var', '/var/homebrew', '/var/homebrew/pinned'])
for (const phase of ['staged', 'quarantined', 'recovery']) for (const change of ['mode', 'group', 'identity', 'owner']) {
    test(`Darwin directory ${relative || 'prefix'} ${change} change invalidates ${phase} snapshots`, async t => {
        const f = darwinHomebrewFixture(t, '1.18.33', '_2'), boundary = f.prefix + relative;
        const native = f.mapped(f.cellar + '/bin/opencode'), before = fs.readFileSync(native);
        const mutate = () => {
            if (change === 'mode') fs.chmodSync(f.mapped(boundary), 0o755);
            else {
                const key = change === 'owner' ? 'uid' : change === 'group' ? 'gid' : 'ino';
                f.statOverrides.set(boundary, {[key]: fs.lstatSync(f.mapped(boundary))[key] + 1});
            }
        };
        f.afterQuarantine = () => { if (phase === 'quarantined') mutate(); };
        f.duringProbe = count => {
            if (phase === 'staged' && count === 1) mutate();
            if (phase === 'recovery' && count === 2) { mutate(); throw new Error('INERT failed probe'); }
        };
        await assert.rejects(f.api.install(f.options), error => {
            const expected = phase === 'staged' ? 'policy-failed:homebrew-preflight:brew-snapshot-changed'
                : phase === 'quarantined' ? 'recovery-required:policy-failed:homebrew-preflight:brew-snapshot-changed'
                : 'recovery-required:policy-failed:installation:version-probe';
            assert.equal(f.api.failureResult(error), 'opencode-cli:' + expected); return true;
        });
        assert.deepEqual(fs.readFileSync(native), before);
        assert.equal(fs.existsSync(f.dest), false);
        assert.equal(fs.existsSync(f.mapped(f.command)), phase === 'staged');
        if (change === 'mode') assert.equal(fs.statSync(f.mapped(boundary)).mode & 0o777, 0o755);
        else assert.ok(f.statOverrides.has(boundary), 'independent metadata change remains intact');
    });
}
test('revision-bearing Homebrew command survives failed replacement artifact staging without a probe', async t => {
    const f = darwinHomebrewFixture(t, '1.18.30', '_2');
    const url = 'https://registry.npmjs.org/@opencode/cli-darwin-arm64/2.0.18';
    const metadata = JSON.parse(f.responses.get(url));
    metadata.dist.integrity = 'sha512-' + Buffer.alloc(64).toString('base64');
    f.responses.set(url, Buffer.from(JSON.stringify(metadata)));
    await assert.rejects(f.api.install(f.options), error => {
        assert.equal(f.api.failureResult(error), 'opencode-cli:policy-failed:installation:integrity'); return true;
    });
    assert.equal(fs.readlinkSync(f.mapped(f.command)), '../Cellar/opencode/1.18.30_2/bin/opencode');
    assert.equal(f.probes.length, 0);
    assert.deepEqual(fs.readdirSync(path.dirname(f.dest)), []);
});
test('revision-bearing Homebrew command is restored exactly after an independently occupied publication destination', async t => {
    const f = darwinHomebrewFixture(t, '1.18.30', '_2');
    const receipt = f.mapped(f.cellar + '/INSTALL_RECEIPT.json'), before = fs.readFileSync(receipt);
    f.afterQuarantine = () => fs.writeFileSync(f.dest, 'INERT independent command', {mode: 0o755});
    await assert.rejects(f.api.install(f.options), error => {
        assert.equal(f.api.failureResult(error), 'opencode-cli:policy-failed:installation:native-EEXIST'); return true;
    });
    assert.equal(fs.readlinkSync(f.mapped(f.command)), '../Cellar/opencode/1.18.30_2/bin/opencode');
    assert.deepEqual(fs.readFileSync(receipt), before);
    assert.equal(fs.readFileSync(f.dest, 'utf8'), 'INERT independent command');
    assert.deepEqual(fs.readdirSync(f.mapped(f.prefix + '/bin')), ['opencode']);
    assert.deepEqual(fs.readdirSync(path.dirname(f.dest)), ['opencode']);
});
for (const phase of ['staged', 'promoted']) test(`Darwin directory exception preserves rollback after ${phase} probe failure`, async t => {
    const f = darwinHomebrewFixture(t, '1.18.33', '_2'), before = fs.readlinkSync(f.mapped(f.command));
    f.duringProbe = count => { if (count === (phase === 'staged' ? 1 : 2)) throw new Error('INERT failed probe'); };
    await assert.rejects(f.api.install(f.options), /version-probe/);
    assert.equal(fs.readlinkSync(f.mapped(f.command)), before);
    assert.equal(fs.existsSync(f.dest), false);
    assert.equal(fs.statSync(f.mapped(f.prefix + '/bin')).mode & 0o777, 0o775);
});
for (const [change, reason] of [['identity', 'unverified-copy'], ['pin', 'pinned'], ['receipt-link', 'brew-path'],
    ['malformed-receipt', 'metadata'], ['missing-receipt', 'native-ENOENT'], ['custom-tap', 'brew-origin'], ['custom-link', 'brew-command'],
    ['receipt-world-write', 'brew-path'], ['receipt-foreign-owner', 'brew-path'], ['receipt-root-group-write', 'brew-path'],
    ['receipt-hardlink', 'brew-path'], ['outside-prefix-root-group-write', 'brew-path']]) {
    test(`Homebrew preserves ${change} without executing any command`, async t => {
        const f = homebrewFixture(t, 'linux', '/home/linuxbrew/.linuxbrew', '1.18.33', '_2'), native = f.cellar + '/bin/opencode', receipt = f.cellar + '/INSTALL_RECEIPT.json';
        if (change === 'identity') { fs.chmodSync(f.mapped(native), 0o755); f.put(native, 'INERT custom command', 0o555); }
        if (change === 'pin') f.put(f.prefix + '/var/homebrew/pinned/opencode', 'inert pin');
        if (change === 'receipt-link') {
            fs.renameSync(f.mapped(receipt), f.mapped(receipt + '.saved'));
            fs.symlinkSync('INSTALL_RECEIPT.json.saved', f.mapped(receipt));
        }
        if (change === 'malformed-receipt') f.put(receipt, '{malformed');
        if (change === 'missing-receipt') fs.unlinkSync(f.mapped(receipt));
        if (change === 'custom-tap') f.put(receipt, '{"source":{"tap":"custom/tap"}}');
        if (change === 'custom-link') {
            fs.unlinkSync(f.mapped(f.command)); fs.symlinkSync('../custom/opencode', f.mapped(f.command));
        }
        if (change === 'receipt-world-write') fs.chmodSync(f.mapped(receipt), 0o666);
        if (change === 'receipt-foreign-owner') f.statOverrides.set(receipt, {uid: process.getuid()+1});
        if (change === 'receipt-root-group-write') f.statOverrides.set(receipt, {uid: 0});
        if (change === 'receipt-hardlink') fs.linkSync(f.mapped(receipt), f.mapped(receipt + '.linked'));
        if (change === 'outside-prefix-root-group-write') {
            fs.chmodSync(f.mapped('/home/linuxbrew'), 0o775); f.statOverrides.set('/home/linuxbrew', {uid: 0});
        }
        const before = fs.readlinkSync(f.mapped(f.command)), contents = fs.readFileSync(f.mapped(native));
        await assert.rejects(f.api.install(f.options), error => {
            assert.equal(f.api.failureResult(error), `opencode-cli:policy-failed:${reason.startsWith('brew-') || reason.startsWith('native-') ? 'homebrew-preflight' : 'installation'}:${reason}`); return true;
        });
        assert.equal(fs.readlinkSync(f.mapped(f.command)), before);
        assert.deepEqual(fs.readFileSync(f.mapped(native)), contents);
        assert.deepEqual(fs.readdirSync(path.dirname(f.dest)), []);
        assert.equal(f.calls.length, 0);
    });
}
for (const phase of ['before-quarantine', 'before-publication', 'recovery']) {
    for (const change of ['owner', 'group', 'mode', 'path-identity', 'receipt', 'command-bytes', 'command-link', 'pin']) {
        test(`Homebrew preserves independent ${change} changes at ${phase}`, async t => {
            const f = homebrewFixture(t, 'linux', '/home/linuxbrew/.linuxbrew', '1.18.33', '_2'), boundary = f.prefix + '/Cellar';
            let backup, changed, evidence;
            const snapshot = file => {
                const info = fs.lstatSync(f.mapped(file));
                return {uid: info.uid, gid: info.gid, mode: info.mode, ino: info.ino,
                    overrides: {...f.statOverrides.get(file)},
                    contents: info.isSymbolicLink() ? fs.readlinkSync(f.mapped(file)) : info.isFile() ? fs.readFileSync(f.mapped(file)) : null};
            };
            const mutate = () => {
                changed = boundary;
                if (change === 'owner') f.statOverrides.set(boundary, {uid: process.getuid()+1});
                if (change === 'group') f.statOverrides.set(boundary, {gid: process.getgid()+1});
                if (change === 'mode') fs.chmodSync(f.mapped(boundary), 0o755);
                if (change === 'path-identity') {
                    fs.renameSync(f.mapped(boundary), f.mapped(boundary + '-saved'));
                    fs.mkdirSync(f.mapped(boundary), {mode: 0o775});
                }
                if (change === 'receipt') {
                    changed = f.cellar + '/INSTALL_RECEIPT.json'; f.put(changed, '{"source":{"tap":"custom/tap"}}');
                }
                if (change === 'command-bytes') {
                    changed = f.cellar + '/bin/opencode';
                    fs.chmodSync(f.mapped(changed), 0o755); f.put(changed, 'INERT independently changed command', 0o555);
                }
                if (change === 'command-link') {
                    changed = backup || f.command;
                    fs.unlinkSync(f.mapped(changed)); fs.symlinkSync('../independent-target', f.mapped(changed));
                }
                if (change === 'pin') {
                    changed = f.prefix + '/var/homebrew/pinned/opencode'; f.put(changed, 'independent pin');
                }
                evidence = snapshot(changed);
            };
            f.afterQuarantine = file => { backup = file; if (phase === 'before-publication') mutate(); };
            f.duringProbe = count => {
                if (count === 1 && phase === 'before-quarantine') mutate();
                if (count === 2 && phase === 'recovery') { mutate(); throw new Error('INERT promoted probe failure'); }
            };
            await assert.rejects(f.api.install(f.options), error => {
                assert.equal(f.api.failureResult(error), phase === 'before-quarantine'
                    ? 'opencode-cli:policy-failed:homebrew-preflight:brew-snapshot-changed'
                    : phase === 'before-publication' ? 'opencode-cli:recovery-required:policy-failed:homebrew-preflight:brew-snapshot-changed'
                    : 'opencode-cli:recovery-required:policy-failed:installation:version-probe');
                return true;
            });
            assert.deepEqual(snapshot(changed), evidence, 'independent changes must never be repaired or overwritten');
            assert.equal(fs.existsSync(f.dest), false);
            assert.equal(f.probes.length, phase === 'recovery' ? 2 : 1);
            const bin = path.dirname(f.dest), lock = path.join(bin, '.setup-opencode-cli.lock');
            if (phase === 'before-quarantine') {
                assert.ok(fs.lstatSync(f.mapped(f.command)).isSymbolicLink());
                assert.deepEqual(fs.readdirSync(bin), []);
            } else {
                assert.ok(fs.lstatSync(f.mapped(backup)).isSymbolicLink());
                assert.equal(fs.existsSync(f.mapped(f.command)), false);
                assert.ok(fs.existsSync(lock));
                const stage = fs.readdirSync(bin).find(name => name.startsWith('.setup-opencode-') && name !== '.setup-opencode-cli.lock');
                assert.deepEqual(JSON.parse(fs.readFileSync(path.join(bin, stage, 'recovery.json'))), [[f.command, backup]]);
            }
        });
    }
}
for (const phase of ['staged', 'promoted']) test(`Homebrew ${phase} probe failure safely restores the original verified command`, async t => {
    const f = homebrewFixture(t, 'linux', '/home/linuxbrew/.linuxbrew', '1.18.33', '_2'), original = fs.readFileSync(f.mapped(f.cellar + '/bin/opencode'));
    f.duringProbe = count => { if (count === (phase === 'staged' ? 1 : 2)) throw new Error('INERT probe failure'); };
    await assert.rejects(f.api.install(f.options), /version-probe/);
    assert.equal(fs.readlinkSync(f.mapped(f.command)), '../Cellar/opencode/1.18.33_2/bin/opencode');
    assert.deepEqual(fs.readFileSync(f.mapped(f.cellar + '/bin/opencode')), original);
    assert.deepEqual(fs.readdirSync(path.dirname(f.dest)), []);
    assert.deepEqual(fs.readdirSync(f.mapped(f.prefix + '/bin')), ['opencode']);
});
test('typed policy/native diagnostics do not accept forged exceptions or malformed reasons', async t => {
    for (const error of [new Error('brew-path'), new Error('pinned'), {reason: 'brew-group-shared', operation: 'homebrew-preflight'},
        {code: 'EACCES', message: 'SECRET'}, new Error('opencode-cli:policy-failed:homebrew-preflight:brew-path')]) {
        assert.equal(policy.failureResult(error), 'opencode-cli:failed');
    }
    const f = fixture(t); fs.chmodSync(f.home, 0o777);
    await assert.rejects(policy.install(f.options), error => {
        assert.equal(policy.failureResult(error), 'opencode-cli:policy-failed:installation:unsafe-path');
        for (const reason of [null, 'brew-group-shared', 'brew-identity-source', 'brew-acl-present', 'brew-acl-unverified',
            'brew-proof-unverified', 'brew-proof-tool', 'brew-process-churn', 'SECRET']) {
            error.reason = reason;
            assert.equal(policy.failureResult(error), 'opencode-cli:failed');
        }
        return true;
    });
});
test('Homebrew migration retains receipt/identity/pin checks but ignores compiler readiness', async t => {
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
        if (mode === 'migrate' || mode === 'unready') {
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
    const f = fixture(t), {api} = virtualPolicy(f, {platform: 'win32', env: {SETUP_OPENCODE_ACL_VERIFIED: '1',
        SETUP_OPENCODE_SHELL: '/fixture/pwsh.exe', SETUP_OPENCODE_FRESH_PATH: '/fixture/windows'}});
    f.shellSelection = f.dest + '.exe';
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
    f.options.verifySessionSelection = async expected => expected === f.dest + '.exe';
    assert.equal(await api.install(f.options), 'migrated');
    assert.deepEqual(fs.readFileSync(f.dest + '.exe'), modern);
    assert.deepEqual(fs.readFileSync(path.join(root, 'bin/opencode.exe')), bytes);
});
test('unsupported architecture performs no HTTP or filesystem provisioning', async () => {
    assert.equal(await policy.install({target: null, home: '/does/not/exist', get: () => assert.fail('HTTP')}), 'unsupported');
});
