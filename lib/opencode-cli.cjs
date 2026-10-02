// Embedded in all six entry points by tools/embed-opencode-cli.py.
// Version 4 | Last changed: Accept account-owned Linux Homebrew group write without privacy proof.
// Installation only: never import application code or inherit its environment.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const https = require('node:https');
const crypto = require('node:crypto');
const zlib = require('node:zlib');
const cp = require('node:child_process');
const policyReasons = new Set(('archive archive-header archive-path archive-tail archive-truncated archive-type artifact-identity artifact-metadata ' +
    'brew-command brew-origin brew-path brew-readiness brew-snapshot-changed ' +
    'changed-copy changed-receipt custom-link custom-prefix custom-wrapper duplicate-metadata integrity libc metadata missing-binary outside-home package-conflict pinned receipt ' +
    'recovery-occupied relative-path release-metadata shadowed shadowed-newer unreachable unsafe-file unsafe-path unverified-copy url version version-probe windows-acl').split(' '));
const nativeCodes = new Set('EACCES EPERM ENOENT EIO EEXIST ENOTDIR ELOOP ENOSPC EROFS ETIMEDOUT ENOBUFS'.split(' '));
class PolicyError extends Error {
    constructor(reason, operation = reason.startsWith('brew-') ? 'homebrew-preflight' : 'installation') {
        super(reason); this.reason = reason; this.operation = operation;
    }
}
const fail = reason => { throw new PolicyError(reason); };
const nativeFailure = (operation, error) => nativeCodes.has(error?.code) ? new PolicyError(`native-${error.code}`, operation) : error;
const version = value => {
    if (typeof value !== 'string' || !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value)) fail('version');
    const parts = value.split('.').map(Number);
    if (parts.some(n => !Number.isSafeInteger(n))) fail('version');
    return parts;
};
const compare = (a, b) => {
    const aa = version(a), bb = version(b);
    for (let i = 0; i < 3; i++) if (aa[i] !== bb[i]) return Math.sign(aa[i] - bb[i]);
    return 0;
};
const samePath = (a, b) => process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b;
const digest = bytes => crypto.createHash('sha512').update(bytes).digest('base64');
function json(bytes) {
    const text = bytes.toString(); let value;
    try { value = JSON.parse(text); } catch { fail('metadata'); }
    // JSON.parse accepts duplicate keys; that can otherwise erase an explicit pin.
    const stack = [];
    for (const match of text.matchAll(/"(?:\\.|[^"\\])*"|[{}[\],:]|[^\s{}[\],:]+/g)) {
        const token = match[0];
        if (token === '{') stack.push({keys: new Set(), expectingKey: true});
        else if (token === '[') stack.push(null);
        else if (token === '}' || token === ']') stack.pop();
        else if (token === ',' && stack.at(-1)) stack.at(-1).expectingKey = true;
        else if (token.startsWith('"') && stack.at(-1)?.expectingKey) {
            const top = stack.at(-1), key = JSON.parse(token);
            if (top.keys.has(key)) fail('duplicate-metadata');
            top.keys.add(key); top.expectingKey = false;
        }
    }
    return value;
}
function target(platform = process.platform, machine = os.machine(), glibc = process.report.getReport().header.glibcVersionRuntime) {
    const arch = {x86_64: 'x64', AMD64: 'x64', x64: 'x64', arm64: 'arm64', ARM64: 'arm64', aarch64: 'arm64'}[machine];
    if (!arch || !['linux', 'darwin', 'win32'].includes(platform)) return null;
    // Always use the official baseline on x64, including Rosetta. No AVX2 assumption.
    let result = `${platform === 'win32' ? 'windows' : platform}-${arch}${arch === 'x64' ? '-baseline' : ''}`;
    if (platform === 'linux' && !glibc) {
        if (!fs.readdirSync('/lib').some(n => /^ld-musl-(x86_64|aarch64)\.so\.1$/.test(n))) fail('libc');
        result += '-musl';
    }
    return result;
}
// Only these labels/statuses may cross the core-to-shell diagnostic boundary.
class DownloadError extends Error {
    constructor(operation, status) { super('download'); this.operation = operation; this.status = status; }
}
function failureResult(error) {
    if (error?.message === 'recovery-required') return 'opencode-cli:recovery-required';
    if (error instanceof DownloadError && ['latest-release', 'package-index', 'package-version', 'artifact-download', 'download'].includes(error.operation)) {
        const status = Number.isInteger(error.status) && error.status >= 100 && error.status <= 599 ? error.status : 'unknown';
        return `opencode-cli:download-failed:${error.operation}:http-${status}`;
    }
    if (error instanceof PolicyError && typeof error.reason === 'string' && ['homebrew-preflight', 'installation'].includes(error.operation) &&
        (policyReasons.has(error.reason) || (error.reason.startsWith('native-') && nativeCodes.has(error.reason.slice(7))))) {
        return `opencode-cli:policy-failed:${error.operation}:${error.reason}`;
    }
    return 'opencode-cli:failed';
}
function downloadOperation(parsed) {
    if (parsed.hostname === 'opencode.ai') return parsed.pathname === '/update/api/latest/cli/npm' ? 'latest-release' : 'download';
    let pathname;
    try { pathname = decodeURIComponent(parsed.pathname); } catch { fail('url'); }
    // Scoped names may use either a literal or percent-encoded slash. Only whole
    // package indexes support npm's abbreviated media type; versions require JSON.
    if (/^\/(?:@[A-Za-z0-9_.-]+\/)?[A-Za-z0-9_.-]+\/?$/.test(pathname)) return 'package-index';
    if (/^\/(?:@[A-Za-z0-9_.-]+\/)?[A-Za-z0-9_.-]+\/-\/[A-Za-z0-9_.-]+\.tgz$/.test(pathname)) return 'artifact-download';
    if (/^\/(?:@[A-Za-z0-9_.-]+\/)?[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/?$/.test(pathname)) return 'package-version';
    return 'download';
}
function fetchBytes(url, limit = 32 * 1024 * 1024) {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.port ||
        !['registry.npmjs.org', 'opencode.ai'].includes(parsed.hostname)) fail('url');
    const operation = downloadOperation(parsed);
    const accept = operation === 'package-index' ? 'application/vnd.npm.install-v1+json' : operation === 'artifact-download' ? 'application/octet-stream' : 'application/json';
    return new Promise((resolve, reject) => {
        let status;
        const request = https.get(url, {rejectUnauthorized: true, headers: {'User-Agent': 'curl/8.0', Accept: accept}}, response => {
            status = response.statusCode;
            if (status !== 200) { response.resume(); reject(new DownloadError(operation, status)); return; }
            const chunks = []; let length = 0;
            response.on('data', data => {
                length += data.length;
                if (length > limit) request.destroy(new Error('download-size'));
                else chunks.push(data);
            });
            response.on('end', () => resolve(Buffer.concat(chunks)));
            response.on('error', () => reject(new DownloadError(operation, status)));
        });
        const deadline = setTimeout(() => request.destroy(new Error('download-timeout')), 90000);
        request.on('close', () => clearTimeout(deadline));
        request.setTimeout(60000, () => request.destroy(new Error('download-timeout')));
        request.on('error', () => reject(new DownloadError(operation, status)));
    });
}
function unpack(bytes) {
    let tar;
    try { tar = zlib.gunzipSync(bytes, {maxOutputLength: 512 * 1024 * 1024}); } catch { fail('archive'); }
    const files = new Map(); let ended = false;
    for (let offset = 0; offset + 512 <= tar.length;) {
        const header = tar.subarray(offset, offset + 512); offset += 512;
        if (header.every(b => b === 0)) { ended = true; if (tar.subarray(offset).some(b => b !== 0)) fail('archive-tail'); break; }
        const text = (start, end) => header.subarray(start, end).toString().replace(/\0.*$/s, '');
        const name = text(0, 100), sizeText = text(124, 136).trim(), checksum = text(148, 156).trim();
        if (!/^[0-7]+$/.test(sizeText) || !/^[0-7]+$/.test(checksum)) fail('archive-header');
        const sum = header.reduce((n, b, i) => n + (i >= 148 && i < 156 ? 32 : b), 0);
        if (sum !== parseInt(checksum, 8) || text(345, 500) || text(157, 257)) fail('archive-header');
        if (!/^package\/(?:[A-Za-z0-9_@.-]+\/)*[A-Za-z0-9_.-]+\/?$/.test(name) ||
            name.split('/').some(p => p === '..' || p === '.') || files.has(name)) fail('archive-path');
        const size = parseInt(sizeText, 8), type = text(156, 157);
        if (!['', '0', '5'].includes(type) || (type === '5' && size) || offset + size > tar.length) fail('archive-type');
        files.set(name, tar.subarray(offset, offset + size));
        offset += Math.ceil(size / 512) * 512;
    }
    if (!ended) fail('archive-truncated');
    return files;
}
async function artifact(name, release, get = fetchBytes) {
    version(release);
    const metadata = json(await get(`https://registry.npmjs.org/${name}/${release}`));
    const basename = name.split('/').pop();
    if (metadata.name !== name || metadata.version !== release ||
        metadata.dist?.tarball !== `https://registry.npmjs.org/${name}/-/${basename}-${release}.tgz` ||
        !/^sha512-[A-Za-z0-9+/]{86}==$/.test(metadata.dist?.integrity || '')) fail('artifact-metadata');
    const bytes = await get(metadata.dist.tarball, 256 * 1024 * 1024);
    if (`sha512-${digest(bytes)}` !== metadata.dist.integrity) fail('integrity');
    const files = unpack(bytes), manifest = json(files.get('package/package.json') || 'null');
    if (manifest?.name !== name || manifest.version !== release) fail('artifact-identity');
    return files;
}
function safePath(file, home, leafLink = false) {
    // Resolve only the account HOME boundary (including Bazzite's system alias).
    const relative = path.relative(home, file);
    if (relative.startsWith('..') || path.isAbsolute(relative)) fail('outside-home');
    const chain = [home];
    for (const part of relative.split(path.sep).filter(Boolean)) chain.push(path.join(chain.at(-1), part));
    for (const item of chain) {
        let st;
        try { st = fs.lstatSync(item); } catch (e) { if (e.code === 'ENOENT') continue; throw e; }
        if ((st.isSymbolicLink() && !(leafLink && item === file)) ||
            (!st.isSymbolicLink() && !st.isDirectory() && !st.isFile()) ||
            (process.platform !== 'win32' && (st.uid !== process.getuid() || (!st.isSymbolicLink() && (st.mode & 0o022))))) fail('unsafe-path');
    }
}
function boundedRead(file) {
    const before = fs.lstatSync(file);
    if (!before.isFile() || before.size > 512 * 1024 * 1024) fail('unsafe-file');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK | (fs.constants.O_NOFOLLOW || 0));
    try {
        const opened = fs.fstatSync(fd);
        if (!opened.isFile() || opened.dev !== before.dev || opened.ino !== before.ino || opened.size !== before.size) fail('changed-copy');
        const bytes = fs.readFileSync(fd), after = fs.fstatSync(fd);
        if (bytes.length !== before.size || after.size !== before.size || after.mtimeMs !== before.mtimeMs) fail('changed-copy');
        return bytes;
    } finally { fs.closeSync(fd); }
}
function commands(home, env = process.env) {
    const dirs = new Set([path.join(home, '.local/bin'), path.join(home, '.opencode/bin'), path.join(home, '.bun/bin')]);
    for (const dir of (env.PATH || '').split(path.delimiter)) {
        if (!dir && process.platform === 'win32') continue;
        if (!dir || !path.isAbsolute(dir)) fail('relative-path');
        dirs.add(dir.startsWith(env.HOME + path.sep) ? path.join(home, path.relative(env.HOME, dir)) : dir);
    }
    const names = process.platform === 'win32' ? ['opencode.exe', 'opencode.cmd', 'opencode.ps1', 'opencode'] : ['opencode'];
    const result = [];
    for (const dir of dirs) for (const name of names) {
        const file = path.join(dir, name);
        try { fs.lstatSync(file); result.push(file); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
    return [...new Map(result.map(file => [process.platform === 'win32' ? file.toLowerCase() : file, file])).values()];
}
function probe(file, release, workspace) {
    const isolated = fs.mkdtempSync(path.join(workspace, 'probe-'));
    const env = {HOME: isolated, USERPROFILE: isolated, XDG_CONFIG_HOME: isolated, XDG_DATA_HOME: isolated,
        XDG_CACHE_HOME: isolated, XDG_STATE_HOME: isolated, APPDATA: isolated, LOCALAPPDATA: isolated,
        TMPDIR: isolated, TMP: isolated, TEMP: isolated, PATH: path.dirname(file), LANG: 'C', NO_COLOR: '1'};
    if (process.platform === 'win32') env.SystemRoot = process.env.SystemRoot;
    let output;
    try { output = cp.execFileSync(file, ['--version'], {cwd: isolated, env, timeout: 20000, maxBuffer: 1024,
        stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true}).toString().trim(); } catch { fail('version-probe'); }
    if (output !== release && output !== `opencode v${release}`) fail('version-probe');
}
const brewFingerprint = s => s && (s.isDirectory() ? ['dev', 'ino', 'uid', 'gid', 'mode'] :
    ['dev', 'ino', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtimeMs', 'ctimeMs']).map(key => s[key]);
const sameBrew = (a, b) => JSON.stringify(brewFingerprint(a)) === JSON.stringify(brewFingerprint(b));
function brewPermissions(file, info) {
    if (![0, process.getuid()].includes(info.uid) || (!info.isSymbolicLink() && (info.mode & 0o002))) fail('brew-path');
    if (!info.isSymbolicLink() && (info.mode & 0o020)) {
        if (process.platform !== 'linux' || info.uid === 0 || info.uid !== process.getuid() ||
            !(file === '/home/linuxbrew/.linuxbrew' || file.startsWith('/home/linuxbrew/.linuxbrew/'))) fail('brew-path');
        // Scoped single-human-user policy: group privacy is not a prerequisite.
        // Keep ownership/mode/identity snapshots; do not infer exclusive access.
    }
}
function checkBrewTrust(trust, moved = false) {
    for (const [file, before] of trust.snapshots) {
        if (moved && file === trust.command) continue;
        let now = null;
        try { now = fs.lstatSync(file); } catch (error) { if (error.code !== 'ENOENT') throw error; }
        if (!sameBrew(before, now)) fail('brew-snapshot-changed');
        if (now) brewPermissions(file, now);
    }
    if (!moved && fs.readlinkSync(trust.command) !== trust.link) fail('brew-snapshot-changed');
}
function checkBrewBackup(item, backup) {
    checkBrewTrust(item.brewTrust, true);
    const before = item.brewTrust.snapshots.get(item.file), now = fs.lstatSync(backup);
    // Renaming can change ctime; every other link identity field must survive.
    if (!['dev', 'ino', 'uid', 'gid', 'mode', 'nlink', 'size', 'mtimeMs'].every(key => before[key] === now[key]) ||
        !now.isSymbolicLink() || fs.readlinkSync(backup) !== item.brewTrust.link) fail('brew-snapshot-changed');
}
function brewCopy(file) {
    try { return inspectBrewCopy(file); } catch (error) { throw nativeFailure('homebrew-preflight', error); }
}
function inspectBrewCopy(file) {
    if (process.platform === 'win32') return null;
    const prefix = ['/opt/homebrew', '/usr/local', '/home/linuxbrew/.linuxbrew'].find(p => file === `${p}/bin/opencode`);
    if (!prefix) return null;
    const snapshots = new Map();
    function inspect(candidate, kind, optional = false) {
        const chain = ['/'];
        for (const part of candidate.split('/').filter(Boolean)) chain.push(path.join(chain.at(-1), part));
        for (const current of chain) {
            let info = null;
            try { info = fs.lstatSync(current); } catch (error) { if (!optional || error.code !== 'ENOENT') throw error; }
            if (snapshots.has(current) && !sameBrew(snapshots.get(current), info)) fail('brew-snapshot-changed');
            if (!info) { snapshots.set(current, null); return false; }
            const leaf = current === candidate;
            if (leaf && kind === 'pin') fail('pinned');
            if (!(leaf && kind === 'link' ? info.isSymbolicLink() : leaf && kind === 'file' ? info.isFile() && info.nlink === 1 : info.isDirectory())) fail('brew-path');
            if (!snapshots.has(current)) brewPermissions(current, info);
            snapshots.set(current, info);
        }
        return true;
    }
    inspect(file, 'link');
    const link = fs.readlinkSync(file);
    const binary = path.resolve(path.dirname(file), link);
    const match = binary.match(new RegExp(`^${prefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}/Cellar/opencode/([0-9.]+)/bin/opencode$`));
    if (!match) fail('brew-command');
    version(match[1]);
    const receiptPath = path.join(path.dirname(path.dirname(binary)), 'INSTALL_RECEIPT.json');
    inspect(binary, 'file'); inspect(receiptPath, 'file');
    const receipt = json(boundedRead(receiptPath));
    if (receipt?.source?.tap !== 'anomalyco/tap') fail('brew-origin');
    inspect(path.join(prefix, 'var/homebrew/pinned/opencode'), 'pin', true);
    if (process.platform === 'darwin' && process.env.SETUP_OPENCODE_BREW_READY !== '1') fail('brew-readiness');
    const trust = {command: file, link, snapshots};
    checkBrewTrust(trust);
    return {binary, release: match[1], route: 'homebrew', trust};
}
// Exact native (no-shebang) npm cmd-shim templates. Customized/older wrappers
// remain conflicts rather than being interpreted or executed to discover identity.
function windowsNpmShims() {
    const relative = 'node_modules/opencode-ai/bin/opencode.exe';
    const head = '@ECHO off\r\nGOTO start\r\n:find_dp0\r\nSET dp0=%~dp0\r\nEXIT /b\r\n:start\r\nSETLOCAL\r\nCALL :find_dp0\r\n';
    return {
        'opencode.cmd': head + `"%dp0%\\${relative.replaceAll('/', '\\')}"   %*\r\n`,
        opencode: '#!/bin/sh\n' + 'basedir=$(dirname "$(echo "$0" | sed -e \'s,\\\\,/,g\')")\n\n' +
            'case `uname` in\n    *CYGWIN*|*MINGW*|*MSYS*)\n        if command -v cygpath > /dev/null 2>&1; then\n' +
            '            basedir=`cygpath -w "$basedir"`\n        fi\n    ;;\nesac\n\n' + `exec "$basedir/${relative}"   "$@"\n`,
        'opencode.ps1': '#!/usr/bin/env pwsh\n$basedir=Split-Path $MyInvocation.MyCommand.Definition -Parent\n\n' +
            '$exe=""\nif ($PSVersionTable.PSVersion -lt "6.0" -or $IsWindows) {\n' +
            '  # Fix case when both the Windows and Linux builds of Node\n  # are installed in the same directory\n  $exe=".exe"\n}\n' +
            '# Support pipeline input\nif ($MyInvocation.ExpectingInput) {\n' + `  $input | & "$basedir/${relative}"   $args\n` +
            `} else {\n  & "$basedir/${relative}"   $args\n}\nexit $LASTEXITCODE\n`,
    };
}
function packageCommandDirectory(root, home) {
    if (process.platform !== 'win32' && samePath(root, path.join(home, '.local/lib/node_modules/opencode-ai'))) return path.join(home, '.local/bin');
    if (samePath(root, path.join(home, '.bun/install/global/node_modules/opencode-ai'))) return path.join(home, '.bun/bin');
    const relative = path.relative(home, root).replaceAll('\\', '/');
    if (process.platform !== 'win32' && /^\.local\/share\/mise\/installs\/node\/\d+(?:\.\d+){0,2}\/lib\/node_modules\/opencode-ai$/.test(relative)) {
        return path.join(path.dirname(path.dirname(path.dirname(root))), 'bin');
    }
    if (process.platform === 'win32') {
        const npm = path.join(process.env.APPDATA || path.join(home, 'AppData/Roaming'), 'npm');
        if (samePath(root, path.join(npm, 'node_modules/opencode-ai'))) return npm;
        const mise = path.join(process.env.LOCALAPPDATA || path.join(home, 'AppData/Local'), 'mise/installs/node');
        const prefix = path.dirname(path.dirname(root));
        if (/^\d+(?:\.\d+){0,2}$/.test(path.relative(mise, prefix)) && samePath(root, path.join(prefix, 'node_modules/opencode-ai'))) return prefix;
    }
    fail('custom-prefix');
}
async function identify(file, home, nativeTarget, get) {
    const brew = brewCopy(file);
    if (!brew) safePath(file, home, true);
    let binary = brew?.binary || file, release = brew?.release, route = brew?.route || 'standalone';
    const st = fs.lstatSync(file);
    let windowsShim = false;
    if (process.platform === 'win32' && !st.isSymbolicLink() && path.basename(file) !== 'opencode.exe') {
        const expected = windowsNpmShims()[path.basename(file)];
        if (!expected || !boundedRead(file).equals(Buffer.from(expected))) fail('custom-wrapper');
        binary = path.join(path.dirname(file), 'node_modules/opencode-ai/bin/opencode.exe');
        windowsShim = true;
    }
    if ((st.isSymbolicLink() && !brew) || windowsShim) {
        if (!windowsShim) binary = fs.realpathSync(file);
        const match = binary.match(/^(.*[\\/]node_modules[\\/]opencode-ai)[\\/]bin[\\/]opencode(?:\.exe)?$/);
        if (!match) fail('custom-link');
        const root = match[1]; safePath(root, home); safePath(binary, home);
        if (!samePath(path.dirname(file), packageCommandDirectory(root, home))) fail('custom-prefix');
        const packageMetadata = path.join(root, 'package.json'); safePath(packageMetadata, home);
        const pkg = json(boundedRead(packageMetadata));
        if (pkg.name !== 'opencode-ai' || version(pkg.version)[0] !== 1) fail('package-conflict');
        release = pkg.version; route = 'package';
        const manifest = path.join(path.dirname(path.dirname(root)), 'package.json');
        if (fs.existsSync(manifest)) {
            safePath(manifest, home);
            const policy = json(boundedRead(manifest));
            const selected = policy.dependencies?.['opencode-ai'];
            if (selected && !['latest', '*'].includes(selected) && !/^[~^]1\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(selected)) fail('pinned');
            if (policy.overrides?.['opencode-ai'] || policy.resolutions?.['opencode-ai']) fail('pinned');
        }
        if (path.extname(binary) !== '.exe') {
            const published = await artifact('opencode-ai', release, get);
            if (!published.get(`package/bin/${path.basename(binary)}`)?.equals(boundedRead(binary))) fail('custom-wrapper');
            binary = path.join(root, 'bin/.opencode');
        }
        safePath(binary, home);
    } else if (!brew && !['.local/bin', '.opencode/bin', '.bun/bin'].some(dir => samePath(path.dirname(file), path.join(home, dir)))) {
        fail('custom-prefix');
    }
    const bytes = boundedRead(binary);
    // Package metadata is only a hint. Identity always requires official native bytes.
    const content = release ? '' : bytes.toString('latin1');
    // Official Bun builds embed this execution argument. It is only a version
    // hint: the native bytes must still match the published platform artifact.
    const hints = [...new Set([...content.matchAll(/--user-agent=opencode\/([1-9]\d*\.\d+\.\d+)(?=[\x00\s"'\\])/g)].map(match => match[1]))];
    let candidates = release ? [release] : hints.length === 1 ? hints : [...new Set(content.match(/\b[1-9]\d?\.\d{1,4}\.\d{1,4}\b/g) || [])];
    if (!release && hints.length !== 1) {
        const registry = json(await get('https://registry.npmjs.org/opencode-ai'));
        const modern = json(await get('https://registry.npmjs.org/@opencode/cli'));
        candidates = candidates.filter(v => Object.hasOwn(v.startsWith('1.') ? registry.versions || {} : modern.versions || {}, v));
        if (!candidates.length || candidates.length > 8) fail('unverified-copy');
    }
    const variants = [nativeTarget, nativeTarget.replace('-baseline', '')];
    if (nativeTarget.startsWith('linux-')) {
        for (const variant of [...variants]) variants.push(variant.endsWith('-musl') ? variant.slice(0, -5) : variant + '-musl');
    } else if (/^(darwin|windows)-arm64$/.test(nativeTarget)) {
        // Old x64 copies can be present under Rosetta/Windows ARM emulation.
        variants.push(nativeTarget.replace('arm64', 'x64-baseline'), nativeTarget.replace('arm64', 'x64'));
    }
    for (const candidate of candidates) {
        for (const variant of new Set(variants)) {
            let official;
            try { official = await artifact(`${candidate.startsWith('1.') ? 'opencode-' : '@opencode/cli-'}${variant}`, candidate, get); } catch { continue; }
            const executable = official.get(`package/bin/opencode${process.platform === 'win32' ? '.exe' : ''}`);
            if (executable?.equals(bytes)) return {file, binary, release: candidate, route, brewTrust: brew?.trust, nativeHash: digest(bytes), bytes: st.isSymbolicLink() ? null : boundedRead(file), link: st.isSymbolicLink() ? fs.readlinkSync(file) : null};
        }
    }
    fail('unverified-copy');
}
async function install(options = {}) {
    try { return await installChecked(options); } catch (error) { throw nativeFailure('installation', error); }
}
async function installChecked(options) {
    const get = options.get || fetchBytes, runProbe = options.probe || probe;
    const nativeTarget = options.target === undefined ? target() : options.target;
    if (!nativeTarget) return 'unsupported';
    const homeInput = options.home || os.homedir(), home = fs.realpathSync(homeInput);
    safePath(home, home);
    if (process.platform === 'win32' && process.env.SETUP_OPENCODE_ACL_VERIFIED !== '1') fail('windows-acl');
    const latest = json(await get('https://opencode.ai/update/api/latest/cli/npm'));
    if (latest.channel !== 'latest' || latest.name !== 'cli' || latest.distribution !== 'npm' ||
        latest.active !== true || latest.minimum !== false || latest.metadata?.package !== '@opencode/cli' || version(latest.version)[0] !== 2) fail('release-metadata');
    const release = latest.version, destination = path.join(home, '.local/bin', process.platform === 'win32' ? 'opencode.exe' : 'opencode');
    const receipt = path.join(home, '.local/bin/.setup-opencode-cli.json');
    safePath(destination, home, true); safePath(receipt, home);
    const found = options.commands || commands(home);
    // Bun can publish a native hardlink rather than a symlink. Preserve its
    // explicit global selection even when command identity comes from bytes.
    if (found.some(file => samePath(path.dirname(file), path.join(home, '.bun/bin')))) {
        const manifest = path.join(home, '.bun/install/global/package.json');
        safePath(manifest, home);
        if (fs.existsSync(manifest)) {
            const policy = json(boundedRead(manifest)), selected = policy.dependencies?.['opencode-ai'];
            if (selected && !['latest', '*'].includes(selected) && !/^[~^]1\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(selected)) fail('pinned');
            if (policy.overrides?.['opencode-ai'] || policy.resolutions?.['opencode-ai']) fail('pinned');
        }
    }
    const reachable = () => (options.path || process.env.PATH || '').split(path.delimiter).some(dir => {
        try { return path.isAbsolute(dir) && samePath(fs.realpathSync(dir), path.dirname(destination)); } catch { return false; }
    });
    let installed = null, installedBytes = null;
    if (fs.existsSync(receipt)) {
        safePath(destination, home);
        const record = json(boundedRead(receipt)); version(record.version);
        if (Object.keys(record).some(key => !['package', 'version', 'sha512', 'pinned'].includes(key)) ||
            (Object.hasOwn(record, 'pinned') && typeof record.pinned !== 'boolean')) fail('receipt');
        if (record.package !== `@opencode/cli-${nativeTarget}` || record.sha512 !== digest(boundedRead(destination))) fail('receipt');
        if (record.pinned === true) fail('pinned');
        const files = await artifact(record.package, record.version, get);
        if (!files.get(`package/bin/${path.basename(destination)}`)?.equals(boundedRead(destination))) fail('unverified-copy');
        installed = record.version;
        installedBytes = boundedRead(destination);
    }
    const old = [];
    for (const file of found) {
        if (installed && samePath(file, destination)) continue;
        old.push(await identify(file, home, nativeTarget, get));
    }
    if (old.some(item => compare(item.release, release) > 0)) {
        if (old.length !== 1 || installed) fail('shadowed-newer');
        return 'newer';
    }
    if (installed && compare(installed, release) >= 0) {
        if (old.length) fail('shadowed');
        if (!reachable()) fail('unreachable');
        // A newer official version is preserved, never rewritten or downgraded.
        if (compare(installed, release) > 0) return 'newer';
        const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'setup-opencode-'));
        try { runProbe(destination, installed, temp); } finally { fs.rmSync(temp, {recursive: true, force: true}); }
        return 'current';
    }
    const files = await artifact(`@opencode/cli-${nativeTarget}`, release, get);
    const bytes = files.get(`package/bin/${path.basename(destination)}`);
    if (!bytes || !bytes.length) fail('missing-binary');
    const bin = path.dirname(destination); safePath(bin, home);
    fs.mkdirSync(bin, {recursive: true, mode: 0o755}); safePath(bin, home);
    const stage = fs.mkdtempSync(path.join(bin, '.setup-opencode-'));
    const staged = path.join(stage, path.basename(destination));
    const backups = []; let promoted = false, completed = false, locked = false;
    const lock = path.join(bin, '.setup-opencode-cli.lock');
    const previousReceipt = fs.existsSync(receipt) ? boundedRead(receipt) : null;
    try {
        fs.mkdirSync(lock, {mode: 0o700}); locked = true;
        fs.writeFileSync(staged, bytes, {mode: 0o755, flag: 'wx'});
        runProbe(staged, release, stage);
        // Preflight ALL copies before moving any commands. Never remove package stores/data.
        for (const item of old) {
            if (item.route === 'homebrew') checkBrewTrust(item.brewTrust);
            else safePath(item.file, home, !!item.link);
            if (item.link ? fs.readlinkSync(item.file) !== item.link : !boundedRead(item.file).equals(item.bytes)) fail('changed-copy');
            if (digest(boundedRead(item.binary)) !== item.nativeHash) fail('changed-copy');
        }
        if (installed) {
            safePath(destination, home);
            if (!boundedRead(destination).equals(installedBytes)) fail('changed-copy');
            old.push({file: destination});
        }
        for (const item of old) {
            if (item.route === 'homebrew') checkBrewTrust(item.brewTrust);
            const backup = item.route === 'homebrew'
                ? path.join(path.dirname(item.file), `.opencode-setup-recovery-${crypto.randomBytes(12).toString('hex')}`)
                : path.join(stage, `previous-${backups.length}`);
            // Journal each intended move before it occurs, for interruption recovery.
            fs.writeFileSync(path.join(stage, 'recovery.json'), JSON.stringify([...backups, [item.file, backup]]), {mode: 0o600});
            fs.renameSync(item.file, backup); backups.push([item.file, backup]);
        }
        // Recheck the read-only Homebrew boundaries even after command quarantine.
        for (const [original, backup] of backups) {
            const item = old.find(entry => entry.file === original);
            if (item?.route === 'homebrew') checkBrewBackup(item, backup);
        }
        // Atomic no-clobber publication: a concurrent/custom destination is never overwritten.
        fs.linkSync(staged, destination); promoted = true;
        fs.unlinkSync(staged);
        runProbe(destination, release, stage);
        // No PATH edits: require the existing user-local directory to be reachable.
        if (!reachable()) fail('unreachable');
        const remaining = options.commands ? [destination] : commands(home);
        if (remaining.some(file => !samePath(file, destination))) fail('shadowed');
        const record = JSON.stringify({package: `@opencode/cli-${nativeTarget}`, version: release, sha512: digest(bytes)}) + '\n';
        const nextReceipt = path.join(stage, 'receipt'); fs.writeFileSync(nextReceipt, record, {mode: 0o600, flag: 'wx'});
        safePath(receipt, home);
        if (previousReceipt ? !boundedRead(receipt).equals(previousReceipt) : fs.existsSync(receipt)) fail('changed-receipt');
        fs.renameSync(nextReceipt, receipt); completed = true;
        return old.length ? 'migrated' : 'installed';
    } finally {
        if (!completed) {
            try {
                if (promoted) {
                    safePath(destination, home);
                    if (!boundedRead(destination).equals(bytes)) fail('changed-copy');
                    fs.unlinkSync(destination);
                }
                for (const [original, backup] of backups.reverse()) {
                    const item = old.find(entry => entry.file === original);
                    if (item?.route === 'homebrew') checkBrewBackup(item, backup);
                    try { fs.lstatSync(original); fail('recovery-occupied'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
                    fs.renameSync(backup, original);
                }
            } catch { fail('recovery-required'); }
        }
        // Retain old commands privately for manual recovery after a successful migration.
        if (completed && backups.length) fs.chmodSync(stage, 0o700);
        else fs.rmSync(stage, {recursive: true, force: true});
        if (locked) fs.rmdirSync(lock);
    }
}
module.exports = {version, compare, target, unpack, artifact, identify, install, commands, safePath, brewCopy, windowsNpmShims, probe, fetchBytes, failureResult};
if (require.main === module || process.argv[1] === '-') install().then(result => console.log(`opencode-cli:${result}`)).catch(error => {
    console.log(failureResult(error));
    process.exitCode = 1;
});
