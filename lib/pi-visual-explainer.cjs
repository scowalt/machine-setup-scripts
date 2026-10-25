'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const SOURCE = 'git:github.com/nicobailon/visual-explainer';
const REPOSITORY = 'nicobailon/visual-explainer';
const PAYLOAD = 'plugins/visual-explainer';
const OPTIONAL = PAYLOAD + '/node_modules';
const MAX_BYTES = 4 * 1024 * 1024;
const fail = reason => { throw new Error(reason); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const same = (a, b) => a && b && ['dev', 'ino', 'mode', 'uid', 'gid'].every(key => a[key] === b[key]) &&
    (a.isDirectory() && b.isDirectory() || ['nlink', 'size', 'mtimeMs', 'ctimeMs'].every(key => a[key] === b[key]));
function stat(file) {
    try { return fs.lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function remember(ctx, file, info) {
    if (ctx.snapshots.has(file)) {
        const before = ctx.snapshots.get(file);
        if (before ? !same(before, info) : info !== null) fail('changed-input');
    } else ctx.snapshots.set(file, info);
}
function recheck(ctx) {
    for (const [file, before] of ctx.snapshots) {
        const after = stat(file);
        if (before ? !same(before, after) : after !== null) fail('changed-input');
    }
}
function absolute(value, home) {
    if (typeof value !== 'string' || !value || /[\x00-\x1f]/.test(value) ||
        value.split(/[\\/]/).some(part => part === '.' || part === '..')) fail('unsafe-profile');
    if (value.startsWith('~/')) value = path.join(home, value.slice(2));
    if (!path.isAbsolute(value)) fail('unsafe-profile');
    if (process.platform === 'win32' && (!/^[A-Za-z]:[\\/]/.test(value) ||
        value.slice(3).split(/[\\/]/).some(part => /[. :]$/.test(part) || part.includes(':')))) fail('unsafe-profile');
    return path.resolve(value);
}
function directory(ctx, file, missing = false) {
    const parts = [];
    for (let current = file; ; current = path.dirname(current)) {
        parts.unshift(current);
        if (path.dirname(current) === current) break;
    }
    let absent = false;
    for (const current of parts) {
        const info = stat(current);
        if (!info) {
            if (!missing) fail('unsafe-directory');
            absent = true;
        } else {
            if (absent) fail('changed-input');
            if (info.isSymbolicLink()) {
                const alias = process.platform === 'linux' && current === '/home' && info.uid === 0 &&
                    ['/var/home', 'var/home'].includes(fs.readlinkSync(current)) && ['/var', '/var/home'].every(parent => {
                        const s = stat(parent);
                        return s?.isDirectory() && !s.isSymbolicLink() && s.uid === 0 && !(s.mode & 0o022);
                    });
                if (!alias) fail('unsafe-directory');
            } else if (!info.isDirectory()) fail('unsafe-directory');
            if (process.platform !== 'win32' && !info.isSymbolicLink()) {
                const stickySystem = info.uid === 0 && (info.mode & 0o1000);
                if (![0, process.getuid()].includes(info.uid) ||
                    (info.mode & (info.uid === 0 ? 0o022 : 0o002)) && !stickySystem) fail('unsafe-directory');
            }
        }
        remember(ctx, current, info);
    }
}
function regular(ctx, file, optional = false) {
    directory(ctx, path.dirname(file));
    const info = stat(file);
    remember(ctx, file, info);
    if (!info && optional) return null;
    if (!info?.isFile() || info.isSymbolicLink() || info.nlink !== 1 || info.size > MAX_BYTES ||
        process.platform !== 'win32' && (info.uid !== process.getuid() || (info.mode & 0o002))) fail('unsafe-file');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
    try {
        if (!same(info, fs.fstatSync(fd))) fail('changed-input');
        const bytes = fs.readFileSync(fd);
        if (!same(info, fs.fstatSync(fd))) fail('changed-input');
        return bytes;
    } finally { fs.closeSync(fd); }
}
function json(bytes) {
    try {
        const value = JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, ''));
        if (!object(value)) fail('invalid-metadata');
        return value;
    } catch { fail('invalid-metadata'); }
}
function acl(ctx) {
    if (process.platform !== 'win32') return '';
    const system = process.env.SystemRoot || 'C:\\Windows';
    if (!/^[A-Za-z]:\\Windows$/i.test(system)) fail('unsafe-acl');
    const program = String.raw`
$ErrorActionPreference='Stop'
try {
    $request=[Console]::In.ReadToEnd() | ConvertFrom-Json
    $user=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $trusted=@($user,'S-1-5-18','S-1-5-32-544')
    $owners=$trusted+@('S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    $result=@()
    foreach ($file in $request.files) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $item=Get-Item -LiteralPath $file -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { exit 1 }
        $acl=Get-Acl -LiteralPath $file
        $account=$file -eq $request.home -or $file.StartsWith($request.home.TrimEnd([char]92)+[char]92,[StringComparison]::OrdinalIgnoreCase)
        $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($account -and $owner -ne $user -or -not $account -and $owner -notin $owners) { exit 1 }
        $writes=[Security.AccessControl.FileSystemRights]'Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
        if ($account) { $writes=$writes -bor [Security.AccessControl.FileSystemRights]::Write }
        foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
            if ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
            if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $trusted -and ($rule.FileSystemRights -band $writes)) { exit 1 }
        }
        if ((Get-Acl -LiteralPath $file).Sddl -cne $acl.Sddl) { exit 1 }
        $result+=,[pscustomobject]@{Path=$file;Acl=$acl.Sddl}
    }
    [Console]::Out.Write((ConvertTo-Json -InputObject $result -Compress))
} catch { exit 1 }
`;
    const result = spawnSync(path.join(system, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(program, 'utf16le').toString('base64')],
        { input: JSON.stringify({ home: ctx.home, files: [...ctx.snapshots.keys()] }),
            env: { SystemRoot: system, WINDIR: system }, encoding: 'utf8', timeout: 15000, maxBuffer: MAX_BYTES, windowsHide: true });
    if (result.error || result.status !== 0) fail('unsafe-acl');
    try { if (!Array.isArray(JSON.parse(result.stdout))) fail('unsafe-acl'); } catch { fail('unsafe-acl'); }
    return result.stdout;
}
function matchesBlob(bytes, blob, windows = process.platform === 'win32') {
    if (bytes.equals(blob)) return true;
    const text = blob.toString('utf8');
    return windows && !text.includes('\0') && !text.includes('\r') && Buffer.from(text).equals(blob) &&
        bytes.equals(Buffer.from(text.replaceAll('\n', '\r\n')));
}
function sourceIdentity(source) {
    if (typeof source !== 'string' || /[\x00-\x20\x7f]/.test(source)) return false;
    const match = source.match(/^(?:git:(?:github\.com\/|git@github\.com:)|(?:git:)?(?:https:\/\/github\.com\/|ssh:\/\/git@github\.com\/))nicobailon\/visual-explainer(?:\.git)?(?:@([A-Za-z0-9_][A-Za-z0-9_.-]*))?$/);
    return Boolean(match && !match[1]?.includes('..'));
}
function selection(settings) {
    if ('packages' in settings && !Array.isArray(settings.packages)) fail('invalid-metadata');
    const matches = [];
    for (const entry of settings.packages || []) {
        const source = typeof entry === 'string' ? entry : object(entry) ? entry.source : null;
        if (typeof source !== 'string' || !source.trim()) fail('invalid-metadata');
        if (sourceIdentity(source)) {
            if (object(entry)) {
                for (const key of ['extensions', 'skills', 'prompts', 'themes']) {
                    if (key in entry && (!Array.isArray(entry[key]) || entry[key].some(value => typeof value !== 'string'))) fail('invalid-metadata');
                }
            }
            matches.push(source);
        } else if (/nicobailon[/:]visual-explainer|^npm:visual-explainer(?:@|$)/i.test(source)) fail('source-conflict');
    }
    if (matches.length > 1) fail('source-conflict');
    return matches[0] || null;
}
function context(homeInput, profileInput, registeredOnly = false) {
    const ctx = { snapshots: new Map() };
    const home = absolute(homeInput);
    directory(ctx, home);
    ctx.home = fs.realpathSync(home);
    if (process.platform !== 'win32' && (process.getuid() === 0 || stat(ctx.home).uid !== process.getuid())) fail('unsafe-profile');
    ctx.agent = absolute(profileInput || path.join(home, '.pi/agent'), home);
    directory(ctx, ctx.agent);
    ctx.agent = fs.realpathSync(ctx.agent);
    const relative = path.relative(ctx.home, ctx.agent);
    if (!relative || relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative) ||
        process.platform !== 'win32' && (stat(ctx.agent).uid !== process.getuid() || (stat(ctx.agent).mode & 0o077))) fail('unsafe-profile');
    ctx.recovery = path.join(ctx.agent, '.setup-visual-explainer-dependencies');
    if (stat(ctx.recovery)) fail('dependency-recovery');
    remember(ctx, ctx.recovery, null);
    const bytes = regular(ctx, path.join(ctx.agent, 'settings.json'), true);
    ctx.settings = bytes ? json(bytes) : {};
    ctx.source = selection(ctx.settings);
    ctx.checkout = path.join(ctx.agent, 'git/github.com', REPOSITORY);
    if (!registeredOnly || ctx.source) {
        directory(ctx, ctx.checkout, true);
        for (const variable of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES']) {
            if (process.env[variable]) fail('redirected-git');
        }
    }
    return ctx;
}
function git(ctx, args, binary = false) {
    const result = spawnSync('git', ['-c', 'core.fsmonitor=false', ...args], {
        cwd: ctx.checkout, env: { ...process.env, GIT_OPTIONAL_LOCKS: '0', GIT_TERMINAL_PROMPT: '0' },
        encoding: binary ? undefined : 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 15000, maxBuffer: MAX_BYTES, windowsHide: true,
    });
    if (result.error || result.status !== 0 || result.signal) fail('unverified-checkout');
    return result.stdout;
}
function checkout(ctx) {
    directory(ctx, path.join(ctx.checkout, '.git'));
    regular(ctx, path.join(ctx.checkout, '.git/config'));
    const identity = git(ctx, ['rev-parse', '--show-toplevel', '--absolute-git-dir', '--git-common-dir']).trim().split(/\r?\n/);
    const dotGit = path.join(ctx.checkout, '.git');
    if (identity.length !== 3 || path.resolve(identity[0]) !== ctx.checkout || path.resolve(identity[1]) !== dotGit ||
        path.resolve(ctx.checkout, identity[2]) !== dotGit ||
        !sourceIdentity(git(ctx, ['remote', 'get-url', 'origin']).trim().replace(/^git@/, 'git:git@'))) fail('unverified-checkout');
    const manifest = regular(ctx, path.join(ctx.checkout, 'package.json'));
    if (!matchesBlob(manifest, git(ctx, ['show', 'HEAD:package.json'], true))) fail('modified-checkout');
    const status = git(ctx, ['status', '--porcelain=v1', '-z', '--untracked-files=normal', '--ignored=matching']);
    for (const record of status.split('\0').filter(Boolean)) {
        if (!['?? node_modules/', '!! node_modules/', '?? package-lock.json', '!! package-lock.json',
            '?? ' + OPTIONAL + '/', '!! ' + OPTIONAL + '/'].includes(record)) fail('modified-checkout');
    }
    const modules = path.join(ctx.checkout, 'node_modules');
    directory(ctx, modules, true);
    const lock = regular(ctx, path.join(ctx.checkout, 'package-lock.json'), true);
    if (lock) json(lock);
    ctx.head = git(ctx, ['rev-parse', 'HEAD']).trim();
    optionalDependencies(ctx);
}
function optionalDependencies(ctx) {
    const root = path.join(ctx.checkout, OPTIONAL);
    directory(ctx, root, true);
    if (!stat(root)) return;
    if (git(ctx, ['ls-files', '--', OPTIONAL]).length) fail('modified-checkout');
    const names = fs.readdirSync(root);
    if (!names.includes('playwright-core') || names.some(name => !['playwright-core', '.bin', '.package-lock.json'].includes(name))) fail('dependency-conflict');
    const manifest = json(regular(ctx, path.join(root, 'playwright-core/package.json')));
    if (manifest.name !== 'playwright-core' || !/^\d+\.\d+\.\d+(?:-[\w.-]+)?$/.test(manifest.version) ||
        manifest.bin?.['playwright-core'] !== 'cli.js') fail('dependency-conflict');
    directory(ctx, path.join(root, '.bin'), true);
    const lock = regular(ctx, path.join(root, '.package-lock.json'), true);
    if (lock) {
        const value = json(lock);
        if (value.lockfileVersion !== 3 || !object(value.packages) || Object.keys(value.packages).length !== 1 ||
            value.packages['node_modules/playwright-core']?.version !== manifest.version ||
            value.packages['node_modules/playwright-core']?.link) fail('dependency-conflict');
    }
    let count = 0, total = 0;
    const walk = (dir, prefix = '') => {
        directory(ctx, dir);
        for (const name of fs.readdirSync(dir)) {
            if (++count > 8192) fail('dependency-conflict');
            const file = path.join(dir, name), relative = prefix + name, info = stat(file);
            if (prefix === '.bin/' && !['playwright-core', 'playwright-core.cmd', 'playwright-core.ps1'].includes(name)) fail('dependency-conflict');
            if (info?.isSymbolicLink()) {
                if (process.platform === 'win32' || relative !== '.bin/playwright-core' || info.uid !== process.getuid() || info.nlink !== 1 ||
                    fs.readlinkSync(file) !== '../playwright-core/cli.js') fail('unsafe-file');
                remember(ctx, file, info);
            } else if (info?.isDirectory()) {
                if (prefix === '.bin/') fail('dependency-conflict');
                walk(file, relative + '/');
            } else {
                total += regular(ctx, file).length;
                if (total > 128 * 1024 * 1024) fail('dependency-conflict');
            }
        }
    };
    walk(root);
    if (!regular(ctx, path.join(root, 'playwright-core/cli.js')).length) fail('dependency-conflict');
    ctx.optional = root;
}
function nativePi(args) {
    const env = { ...process.env };
    delete env.NODE_OPTIONS; delete env.NODE_PATH;
    let command = 'pi', input;
    if (process.platform === 'win32') {
        const system = env.SystemRoot || 'C:\\Windows';
        if (!/^[A-Za-z]:\\Windows$/i.test(system)) fail('unsafe-acl');
        command = path.join(system, 'System32/WindowsPowerShell/v1.0/powershell.exe');
        const code = "$ErrorActionPreference='Stop'; try { $request=[Console]::In.ReadToEnd() | ConvertFrom-Json; & pi @($request.arguments); exit $LASTEXITCODE } catch { exit 1 }";
        input = JSON.stringify({ arguments: args });
        args = ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(code, 'utf16le').toString('base64')];
    }
    const result = spawnSync(command, args, { env, input, stdio: [input ? 'pipe' : 'ignore', 'ignore', 'ignore'], windowsHide: true });
    return !result.error && !result.signal && result.status === 0;
}
function protectDependencies(ctx) {
    if (!ctx.optional) return null;
    const original = ctx.optional, saved = path.join(ctx.recovery, 'node_modules');
    const prefix = original + path.sep;
    recheck(ctx); acl(ctx); recheck(ctx);
    try { fs.mkdirSync(ctx.recovery, { mode: 0o700 }); } catch { fail('dependency-recovery'); }
    const reservation = stat(ctx.recovery);
    ctx.snapshots.set(ctx.recovery, reservation);
    const held = { home: ctx.home, snapshots: new Map() };
    for (const [file, info] of ctx.snapshots) {
        if (file === original || file.startsWith(prefix)) held.snapshots.set(saved + file.slice(original.length), info);
        else if (file === ctx.recovery || info?.isDirectory() && original.startsWith(file.endsWith(path.sep) ? file : file + path.sep)) held.snapshots.set(file, info);
    }
    let moved = false;
    try {
        directory(ctx, ctx.recovery);
        if (process.platform !== 'win32' && (reservation.mode & 0o077)) fail('unsafe-directory');
        acl(ctx); recheck(ctx);
        fs.renameSync(original, saved);
        moved = true;
        recheck(held);
        return { held, original, saved, recovery: ctx.recovery, acl: acl(held) };
    } catch {
        if (!moved && same(reservation, stat(ctx.recovery))) {
            try { fs.rmdirSync(ctx.recovery); } catch {}
        }
        fail('dependency-recovery');
    }
}
function restoreDependencies(transaction) {
    if (!transaction) return;
    const { held, original, saved, recovery } = transaction;
    try {
        recheck(held);
        if (acl(held) !== transaction.acl || stat(original)) fail('dependency-recovery');
        fs.renameSync(saved, original);
        const restored = { home: held.home, snapshots: new Map() };
        for (const [file, info] of held.snapshots) {
            restored.snapshots.set(file === saved || file.startsWith(saved + path.sep) ? original + file.slice(saved.length) : file, info);
        }
        recheck(restored); acl(restored); recheck(restored);
        fs.rmdirSync(recovery);
    } catch { fail('dependency-recovery'); }
}
function maintain(ctx, mode, expected) {
    if (mode === 'install' && expected !== (ctx.source || SOURCE)) fail('unverified-install');
    recheck(ctx); acl(ctx); recheck(ctx);
    const transaction = protectDependencies(ctx);
    let ok = false;
    try { ok = nativePi(mode === 'install' ? ['install', expected, '--no-approve'] : ['update', '--extensions', '--no-approve']); }
    finally { restoreDependencies(transaction); }
    if (!ok) fail('native-command');
    if (mode === 'refresh' && ctx.source) {
        const after = context(ctx.home, ctx.agent);
        if (after.source !== ctx.source || !stat(after.checkout)) fail('unverified-install');
        checkout(after); payload(after); acl(after); recheck(after);
    }
}
function payload(ctx) {
    const manifest = json(regular(ctx, path.join(ctx.checkout, 'package.json')));
    if (manifest.name !== 'visual-explainer' || !/^\d+\.\d+\.\d+(?:-[\w.-]+)?$/.test(manifest.version) || !object(manifest.pi) ||
        ['extensions', 'skills', 'prompts'].some(key => !Array.isArray(manifest.pi[key]) || manifest.pi[key].some(value => typeof value !== 'string')) ||
        !manifest.pi.extensions.includes('./' + PAYLOAD + '/extension.ts') ||
        !manifest.pi.skills?.includes('./' + PAYLOAD) || !manifest.pi.prompts?.includes('./' + PAYLOAD + '/commands')) fail('invalid-payload');
    const tree = new Map();
    let total = 0;
    for (const record of git(ctx, ['ls-tree', '-r', '-z', 'HEAD', '--', PAYLOAD]).split('\0').filter(Boolean)) {
        const match = record.match(/^100(?:644|755) blob [a-f0-9]+\t(.+)$/);
        if (!match || !match[1].startsWith(PAYLOAD + '/') || match[1].split('/').some(part => !part || part === '..') || tree.size >= 2048) fail('invalid-payload');
        const relative = match[1].slice(PAYLOAD.length + 1);
        const bytes = regular(ctx, path.join(ctx.checkout, match[1]));
        if (/^commands\/[^/]+\.md$/.test(relative) && !bytes.length) fail('invalid-payload');
        if (!matchesBlob(bytes, git(ctx, ['show', 'HEAD:' + match[1]], true))) fail('modified-checkout');
        total += bytes.length;
        if (total > 32 * 1024 * 1024) fail('invalid-payload');
        tree.set(relative, bytes);
    }
    for (const name of ['SKILL.md', 'extension.ts', 'commands/diff-review.md', 'commands/generate-web-diagram.md']) {
        if (!tree.get(name)?.length) fail('invalid-payload');
    }
    if (!object(manifest.dependencies)) fail('invalid-payload');
    for (const name of Object.keys(manifest.dependencies)) {
        if (!/^(?:@[a-z0-9._-]+\/)?[a-z0-9._-]+$/i.test(name) || name.split('/').includes('..')) fail('invalid-payload');
        const file = path.join(ctx.checkout, 'node_modules', name, 'package.json');
        if (json(regular(ctx, file)).name !== name) fail('invalid-payload');
    }
    return tree;
}
function migration(ctx, tree) {
    const files = [], directories = [];
    const skill = path.join(ctx.agent, 'skills/visual-explainer');
    directory(ctx, path.dirname(skill), true);
    if (stat(skill)) {
        directory(ctx, skill);
        const found = new Map();
        const pending = [[skill, '']];
        while (pending.length) {
            const [dir, prefix] = pending.pop();
            directories.push(dir);
            if (directories.length + files.length > 4096) fail('legacy-conflict');
            for (const name of fs.readdirSync(dir)) {
                const file = path.join(dir, name), relative = prefix + name;
                const info = stat(file);
                if (info?.isDirectory() && !info.isSymbolicLink()) {
                    if (![...tree.keys()].some(key => key.startsWith(relative + '/'))) fail('legacy-conflict');
                    directory(ctx, file);
                    pending.push([file, relative + '/']);
                } else {
                    const bytes = regular(ctx, file);
                    if (!tree.get(relative)?.equals(bytes)) fail('legacy-conflict');
                    found.set(relative, true); files.push(file);
                }
            }
        }
        if (found.size !== tree.size) fail('legacy-conflict');
    }
    const prompts = path.join(ctx.agent, 'prompts');
    directory(ctx, prompts, true);
    if (stat(prompts)) {
        for (const [relative, bytes] of tree) {
            if (!/^commands\/[^/]+\.md$/.test(relative)) continue;
            const file = path.join(prompts, path.basename(relative));
            const existing = regular(ctx, file, true);
            if (existing) {
                if (!bytes.equals(existing)) fail('legacy-conflict');
                files.push(file);
            }
        }
    }
    const aclBefore = acl(ctx);
    recheck(ctx);
    if (git(ctx, ['rev-parse', 'HEAD']).trim() !== ctx.head) fail('changed-input');
    if (acl(ctx) !== aclBefore) fail('changed-input');
    for (const file of files) {
        recheck(ctx);
        fs.unlinkSync(file);
        ctx.snapshots.set(file, null);
    }
    for (const dir of directories.reverse()) {
        recheck(ctx);
        fs.rmdirSync(dir);
        ctx.snapshots.set(dir, null);
    }
}
function main(args) {
    try {
        const [mode, home, agent, expected] = args;
        if (!['plan', 'finish', 'install', 'refresh'].includes(mode)) fail('invalid-mode');
        const ctx = context(home, agent, mode === 'refresh');
        if ((mode !== 'refresh' || ctx.source) && stat(ctx.checkout)) checkout(ctx);
        if (mode === 'install' || mode === 'refresh') {
            maintain(ctx, mode, expected);
            console.log('ok');
            return 0;
        }
        if (mode === 'finish') {
            if (!ctx.source || ctx.source !== expected || !ctx.head) fail('unverified-install');
            migration(ctx, payload(ctx));
        }
        acl(ctx); recheck(ctx);
        console.log(mode === 'plan' ? 'source:' + (ctx.source || SOURCE) : 'ok');
        return 0;
    } catch (error) {
        const reasons = ['unsafe-profile', 'unsafe-directory', 'unsafe-file', 'unsafe-acl', 'invalid-metadata', 'source-conflict',
            'redirected-git', 'unverified-checkout', 'modified-checkout', 'invalid-payload', 'legacy-conflict', 'changed-input', 'unverified-install', 'invalid-mode',
            'dependency-conflict', 'dependency-recovery', 'native-command'];
        console.log('failed:' + (reasons.includes(error.message) ? error.message : 'unknown'));
        return 1;
    }
}
if (require.main === module || process.argv[1] === '-') process.exitCode = main(process.argv.slice(2));
module.exports = { main, matchesBlob, nativePi };
