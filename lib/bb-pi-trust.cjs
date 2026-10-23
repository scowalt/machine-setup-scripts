'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const MAX_BYTES = 2 * 1024 * 1024;
const fail = reason => { throw new Error(reason); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
const same = (a, b) => a && b && ['dev', 'ino', 'mode', 'uid', 'gid'].every(key => a[key] === b[key]) &&
    (a.isDirectory() && b.isDirectory() || ['nlink', 'size', 'mtimeMs', 'ctimeMs'].every(key => a[key] === b[key]));
function stat(file) {
    try { return fs.lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function absolute(value, home) {
    if (typeof value !== 'string' || !value || /[\x00-\x1f]/.test(value) ||
        value.split(/[\\/]/).some(part => part === '.' || part === '..')) fail('unsafe-path');
    if (value.startsWith('~/') && home) value = path.join(home, value.slice(2));
    if (!path.isAbsolute(value)) fail('unsafe-path');
    if (process.platform === 'win32' && (!/^[A-Za-z]:[\\/]/.test(value) ||
        value.slice(3).split(/[\\/]/).some(part => /[. :]$/.test(part) || part.includes(':')))) fail('unsafe-path');
    return path.resolve(value);
}
function within(root, file) {
    const relative = path.relative(root, file);
    return relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}
function homeAlias(file, info) {
    return process.platform === 'linux' && file === '/home' && info.uid === 0 &&
        ['/var/home', 'var/home'].includes(fs.readlinkSync(file)) && ['/', '/var', '/var/home'].every(parent => {
            const s = stat(parent);
            return s?.isDirectory() && !s.isSymbolicLink() && s.uid === 0 && !(s.mode & 0o022);
        });
}
function directoryChain(file, snapshots, missing = false) {
    const parents = [];
    for (let current = file; ; current = path.dirname(current)) {
        parents.unshift(current);
        if (path.dirname(current) === current) break;
    }
    let absent = false;
    for (const current of parents) {
        const info = stat(current);
        if (!info) {
            if (!missing) fail('unsafe-directory');
            absent = true;
        } else {
            if (absent) fail('changed-input');
            if (info.isSymbolicLink()) {
                if (!homeAlias(current, info)) fail('unsafe-directory');
            } else if (!info.isDirectory()) fail('unsafe-directory');
            if (process.platform !== 'win32' && !info.isSymbolicLink()) {
                const stickySystem = info.uid === 0 && (info.mode & 0o1000);
                if (![0, process.getuid()].includes(info.uid) ||
                    (info.mode & (info.uid === 0 ? 0o022 : 0o002)) && !stickySystem) fail('unsafe-directory');
            }
        }
        if (snapshots.has(current)) {
            const before = snapshots.get(current);
            if (before ? !same(before, info) : info !== null) fail('changed-input');
        } else snapshots.set(current, info);
    }
}
function canonicalFuture(file) {
    const suffix = [];
    let current = file;
    while (!stat(current)) { suffix.unshift(path.basename(current)); current = path.dirname(current); }
    return path.join(fs.realpathSync(current), ...suffix);
}
function recheck(snapshots) {
    for (const [file, before] of snapshots) {
        const after = stat(file);
        if (before ? !same(before, after) : after !== null) fail('changed-input');
    }
}
function windowsAcl(files, accountPaths) {
    if (process.platform !== 'win32') return;
    const system = process.env.SystemRoot || 'C:\\Windows';
    if (!/^[A-Za-z]:\\Windows$/i.test(system)) fail('unsafe-acl');
    const program = String.raw`
$ErrorActionPreference='Stop'
$PSModuleAutoLoadingPreference='None'
try {
    [Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
    foreach ($name in @('Management','Utility','Security')) {
        Import-Module ([IO.Path]::Combine($PSHOME, 'Modules', "Microsoft.PowerShell.$name", "Microsoft.PowerShell.$name.psd1")) -ErrorAction Stop
    }
    $request=[Console]::In.ReadToEnd() | ConvertFrom-Json
    $user=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $trusted=@($user,'S-1-5-18','S-1-5-32-544')
    $systemOwners=$trusted+@('S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    $snapshots=@()
    foreach ($file in $request.files) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $item=Get-Item -LiteralPath $file -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { exit 1 }
        $acl=Get-Acl -LiteralPath $file
        $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        $account=$false
        foreach ($root in $request.accountPaths) {
            $prefix=$root.TrimEnd([char]92)+[char]92
            if ($file -eq $root -or $file.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { $account=$true }
        }
        if ($account -and $owner -ne $user -or -not $account -and $owner -notin $systemOwners) { exit 1 }
        $writes=[Security.AccessControl.FileSystemRights]'Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
        if ($account) { $writes=$writes -bor [Security.AccessControl.FileSystemRights]::Write }
        foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
            if ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
            if ($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $trusted -and ($rule.FileSystemRights -band $writes)) { exit 1 }
        }
        if ((Get-Acl -LiteralPath $file).Sddl -cne $acl.Sddl) { exit 1 }
        $snapshots+=,[pscustomobject][ordered]@{Path=$file;Acl=$acl.Sddl}
    }
    [Console]::Out.Write((ConvertTo-Json -InputObject $snapshots -Compress))
    exit 0
} catch { exit 1 }
`;
    const result = spawnSync(path.join(system, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(program, 'utf16le').toString('base64')],
        { input: JSON.stringify({ files, accountPaths }), env: { SystemRoot: system, WINDIR: system },
            encoding: 'utf8', timeout: 5000, maxBuffer: MAX_BYTES, windowsHide: true });
    if (result.error || result.status !== 0) fail('unsafe-acl');
    try { if (!Array.isArray(JSON.parse(result.stdout))) fail('unsafe-acl'); } catch { fail('unsafe-acl'); }
    return result.stdout;
}
function readTrust(file) {
    const info = stat(file);
    if (!info) return { info: null, text: null, data: {} };
    if (!info.isFile() || info.isSymbolicLink() || info.nlink !== 1 || info.size > MAX_BYTES ||
        process.platform !== 'win32' && (info.uid !== process.getuid() || (info.mode & 0o002))) fail('unsafe-metadata');
    const fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
    let text;
    try {
        if (!same(info, fs.fstatSync(fd))) fail('changed-input');
        text = fs.readFileSync(fd, 'utf8');
        if (!same(info, fs.fstatSync(fd))) fail('changed-input');
    } finally { fs.closeSync(fd); }
    let data;
    try { data = JSON.parse(text.replace(/^\uFEFF/, '')); } catch { fail('invalid-trust'); }
    if (!object(data) || Object.values(data).some(value => value !== true && value !== false && value !== null)) fail('invalid-trust');
    const keys = [...text.matchAll(/("(?:[^"\\]|\\.)*")\s*:/g)].map(match => JSON.parse(match[1]));
    if (new Set(keys).size !== keys.length) fail('invalid-trust');
    return { info, text, data };
}
function decision(data, file) {
    for (let current = file; ; current = path.dirname(current)) {
        if (own(data, current) && typeof data[current] === 'boolean') return data[current];
        if (path.dirname(current) === current) return null;
    }
}
function context(homeInput, dataInput, agentInput) {
    const snapshots = new Map();
    const rawHome = absolute(homeInput);
    directoryChain(rawHome, snapshots);
    const home = fs.realpathSync(rawHome);
    const homeInfo = stat(home);
    if (process.platform !== 'win32' && (process.getuid() === 0 || homeInfo.uid !== process.getuid())) fail('unsafe-home');
    const agent = absolute(agentInput || path.join(home, '.pi/agent'), home);
    directoryChain(agent, snapshots);
    const canonicalAgent = fs.realpathSync(agent);
    if (!within(home, canonicalAgent) || canonicalAgent === home) fail('unsafe-profile');
    const profile = stat(canonicalAgent);
    if (process.platform !== 'win32' && (profile.uid !== process.getuid() || (profile.mode & 0o077))) fail('unsafe-profile');
    const data = absolute(dataInput || path.join(home, '.bb'), home);
    directoryChain(data, snapshots, true);
    if (data === path.parse(data).root || canonicalFuture(data) === home) fail('unsafe-path');
    const roots = [path.join(data, 'plugins/environment-git-worktree/host-data/worktrees'),
        path.join(data, 'thread-storage'), path.join(home, 'Code')];
    for (const root of roots) directoryChain(root, snapshots, true);
    const trustFile = path.join(canonicalAgent, 'trust.json');
    const canonicalRoots = roots.map(canonicalFuture);
    const aclFiles = [...snapshots.keys(), trustFile], aclRoots = [home, data, agent, trustFile];
    const aclSnapshot = windowsAcl(aclFiles, aclRoots);
    recheck(snapshots);
    return { snapshots, agent: canonicalAgent, roots: canonicalRoots, trustFile, aclFiles, aclRoots, aclSnapshot };
}
function mergeTrust(home, data, agent) {
    const ctx = context(home, data, agent);
    const lock = `${ctx.trustFile}.lock`;
    const started = Date.now();
    try { fs.mkdirSync(lock, { mode: 0o700 }); } catch { fail('trust-locked'); }
    const lockInfo = stat(lock);
    let temporary, temporaryInfo;
    try {
        const original = readTrust(ctx.trustFile);
        const next = { ...original.data };
        let changed = false;
        for (const root of ctx.roots) {
            if (decision(next, root) === false || next[root] === true) continue;
            next[root] = true;
            changed = true;
        }
        if (!changed) { recheck(ctx.snapshots); return; }
        temporary = `${ctx.trustFile}.setup-${randomBytes(12).toString('hex')}.tmp`;
        fs.writeFileSync(temporary, JSON.stringify(next, null, 2) + '\n', { flag: 'wx', mode: original.info ? original.info.mode & 0o777 : 0o600 });
        temporaryInfo = stat(temporary);
        windowsAcl([temporary], [temporary]);
        recheck(ctx.snapshots);
        if (windowsAcl(ctx.aclFiles, ctx.aclRoots) !== ctx.aclSnapshot) fail('changed-input');
        if (Date.now() - started >= 4000 || !same(lockInfo, stat(lock))) fail('changed-input');
        const current = readTrust(ctx.trustFile);
        if (original.info ? !same(original.info, current.info) || original.text !== current.text : current.info !== null) fail('changed-input');
        if (!same(temporaryInfo, stat(temporary))) fail('changed-input');
        fs.renameSync(temporary, ctx.trustFile);
        temporary = undefined;
    } finally {
        recheck(ctx.snapshots);
        const currentLock = stat(lock);
        if (Date.now() - started >= 4000 || !same(lockInfo, currentLock) ||
            currentLock.mtimeMs !== lockInfo.mtimeMs || currentLock.ctimeMs !== lockInfo.ctimeMs) fail('changed-input');
        if (temporary) {
            if (!same(temporaryInfo, stat(temporary))) fail('changed-input');
            fs.unlinkSync(temporary);
        }
        fs.rmdirSync(lock);
    }
}
function checkDoctorReport(text, required = []) {
    let report;
    try { report = JSON.parse(text); } catch { fail('invalid-doctor-report'); }
    const states = ['ok', 'blocked', 'disabled', 'failed', 'needs-auth'];
    if (!Array.isArray(report) || report.length === 0 || report.some(row => !object(row) ||
        typeof row.name !== 'string' || !row.name || !states.includes(row.state) ||
        row.state === 'ok' && (!Number.isSafeInteger(row.tools) || row.tools < 0)) ||
        new Set(report.map(row => row.name)).size !== report.length) fail('invalid-doctor-report');
    if (report.some(row => row.state === 'blocked')) fail('doctor-blocked');
    if (report.some(row => !['ok', 'disabled'].includes(row.state))) fail('doctor-unhealthy');
    if (required.some(name => !report.some(row => row.name === name && row.state === 'ok'))) fail('doctor-missing-server');
}
function checkHealth(home, data, agent, cwd, required) {
    const ctx = context(home, data, agent);
    const target = absolute(cwd, absolute(home));
    directoryChain(target, ctx.snapshots);
    const canonical = fs.realpathSync(target);
    if (!ctx.roots.some(root => within(root, canonical))) fail('unsafe-path');
    const cli = path.join(ctx.agent, 'npm/node_modules/pi-mcp-adapter/cli.js');
    directoryChain(path.dirname(cli), ctx.snapshots);
    const info = stat(cli);
    if (!info?.isFile() || info.isSymbolicLink() || info.nlink !== 1 || info.size === 0 ||
        process.platform !== 'win32' && (info.uid !== process.getuid() || (info.mode & 0o002))) fail('unsafe-cli');
    windowsAcl([cli], [cli]);
    recheck(ctx.snapshots);
    const env = { ...process.env, HOME: fs.realpathSync(home), PI_CODING_AGENT_DIR: ctx.agent };
    delete env.NODE_OPTIONS; delete env.NODE_PATH;
    const result = spawnSync(process.execPath, [cli, 'doctor', '--json'],
        { cwd: canonical, env, encoding: 'utf8', timeout: 30000, maxBuffer: MAX_BYTES, windowsHide: true });
    if (result.error || result.status !== 0) fail('doctor-failed');
    checkDoctorReport(result.stdout, required);
}
function main(args) {
    const [mode, home, data, agent, cwd, ...required] = args;
    try {
        if (mode === 'merge') mergeTrust(home, data, agent);
        else if (mode === 'health') checkHealth(home, data, agent, cwd, required);
        else fail('invalid-mode');
        console.log('ok');
        return 0;
    } catch (error) {
        const reasons = ['unsafe-path', 'unsafe-directory', 'unsafe-home', 'unsafe-profile', 'unsafe-acl',
            'unsafe-metadata', 'invalid-trust', 'trust-locked', 'changed-input', 'unsafe-cli', 'doctor-failed',
            'invalid-doctor-report', 'doctor-blocked', 'doctor-unhealthy', 'doctor-missing-server', 'invalid-mode'];
        console.log(`failed:${reasons.includes(error.message) ? error.message : 'unknown'}`);
        return 1;
    }
}
if (require.main === module || process.argv[1] === '-') process.exitCode = main(process.argv.slice(2));
module.exports = { mergeTrust, checkDoctorReport, main };
