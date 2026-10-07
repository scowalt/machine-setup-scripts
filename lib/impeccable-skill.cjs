'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const https = require('node:https');
const fail = reason => { throw new Error(reason); };
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const unique = values => [...new Set(values)];
const semver = value => typeof value === 'string' && /^\d+\.\d+\.\d+$/.test(value);
const [homeInput, activePiInput, blocked, mode, stageInput] = process.argv.slice(2);
const windowsPaths = new Map();
function windowsRecord(file, account = false, link = false) {
    if (process.platform !== 'win32') return;
    const before = windowsPaths.get(file);
    windowsPaths.set(file, {file, account: account || before?.account || file === homeInput || file.startsWith(homeInput + path.sep), link: link && (!before || before.link)});
}
function windowsTrust() {
    if (process.platform !== 'win32') return;
    const program = String.raw`
$ErrorActionPreference='Stop'
$PSModuleAutoLoadingPreference='None'
$pins=@()
try {
    foreach ($name in @('Management','Utility','Security')) {
        Import-Module (Join-Path $PSHOME ('Modules/Microsoft.PowerShell.'+$name+'/Microsoft.PowerShell.'+$name+'.psd1')) -ErrorAction Stop
    }
    Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using Microsoft.Win32.SafeHandles;
public static class ImpeccablePathTrust {
    [StructLayout(LayoutKind.Sequential)]
    public struct Info {
        public uint Attributes, CreatedLow, CreatedHigh, AccessLow, AccessHigh,
            WriteLow, WriteHigh, Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share,
        IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle file, out Info info);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool GetKernelObjectSecurity(SafeFileHandle file, uint information,
        byte[] descriptor, uint length, out uint needed);
    public static SafeFileHandle Pin(string name) {
        if (name.StartsWith("\\\\") || name.Length < 3 || name[1] != ':') throw new InvalidOperationException();
        foreach (string part in name.Substring(3).Split('\\')) {
            if (part.EndsWith(".") || part.EndsWith(" ") || part.Contains(":")) throw new InvalidOperationException();
        }
        var handle=CreateFile(name, 0x20080, 7, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero);
        if (handle.IsInvalid) {
            int error=Marshal.GetLastWin32Error(); handle.Dispose();
            if (error == 2 || error == 3) return null;
            throw new Win32Exception(error);
        }
        return handle;
    }
    public static Info Read(SafeFileHandle handle) {
        Info info;
        if (!GetFileInformationByHandle(handle, out info)) throw new Win32Exception();
        return info;
    }
    public static string Identity(Info info) {
        return info.Volume+":"+info.IndexHigh+":"+info.IndexLow+":"+info.Attributes+":"+info.Links;
    }
    public static FileSystemSecurity Security(SafeFileHandle handle, bool directory) {
        uint needed;
        GetKernelObjectSecurity(handle, 7, null, 0, out needed);
        if (needed == 0 || needed > 65536) throw new InvalidOperationException();
        var bytes=new byte[needed];
        if (!GetKernelObjectSecurity(handle, 7, bytes, needed, out needed)) throw new Win32Exception();
        FileSystemSecurity security=directory ? (FileSystemSecurity)new DirectorySecurity() : new FileSecurity();
        security.SetSecurityDescriptorBinaryForm(bytes);
        return security;
    }
}
"@
    $owner=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $allowed=@($owner,'S-1-5-18','S-1-5-32-544')
    $systemOwners=$allowed+@('S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    $paths=@(ConvertFrom-Json ([Console]::In.ReadToEnd()))
    foreach ($entry in @($paths | Sort-Object { $_.file.Length })) {
        $handle=[ImpeccablePathTrust]::Pin($entry.file)
        if ($null -eq $handle) { continue }
        $pins+=,$handle
        $before=[ImpeccablePathTrust]::Read($handle)
        if (($before.Attributes -band 0x400) -and -not $entry.link) { throw 'reparse' }
        $acl=[ImpeccablePathTrust]::Security($handle,[bool]($before.Attributes -band 0x10))
        $sid=$acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if ($entry.account) { if ($sid -ne $owner) { throw 'owner' } }
        elseif ($systemOwners -notcontains $sid) { throw 'owner' }
        $write=[System.Security.AccessControl.FileSystemRights]'Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
        if ($entry.account) { $write=$write -bor [System.Security.AccessControl.FileSystemRights]::Write }
        foreach ($rule in $acl.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier])) {
            if ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
            if ($rule.AccessControlType -eq 'Allow' -and $allowed -notcontains $rule.IdentityReference.Value -and ($rule.FileSystemRights -band $write)) { throw 'access' }
        }
        $after=[ImpeccablePathTrust]::Read($handle)
        $again=[ImpeccablePathTrust]::Security($handle,[bool]($after.Attributes -band 0x10))
        if ([ImpeccablePathTrust]::Identity($before) -cne [ImpeccablePathTrust]::Identity($after) -or $again.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::All) -cne $acl.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::All)) { throw 'changed' }
    }
    [Console]::Out.Write('trusted')
} catch { exit 1 }
finally { foreach ($handle in $pins) { $handle.Dispose() } }
`;
    const root = process.env.SystemRoot || 'C:\\Windows';
    if (!/^[A-Za-z]:\\Windows$/i.test(root)) fail('windows-acl-unverified');
    const result = require('node:child_process').spawnSync(path.win32.join(root, 'System32/WindowsPowerShell/v1.0/powershell.exe'),
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(program, 'utf16le').toString('base64')], {
            input: JSON.stringify([...windowsPaths.values()]), env: {SystemRoot: root, WINDIR: root},
            encoding: 'utf8', windowsHide: true, shell: false, timeout: 30000, maxBuffer: 1024,
        });
    if (result.status !== 0 || result.stdout !== 'trusted') fail('windows-acl-unverified');
}

function stat(file) {
    try { return fs.lstatSync(file); }
    catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function systemHomeAlias(file, st) {
    if (process.platform !== 'linux' || file !== '/home' || st.uid !== 0) return false;
    if (!['var/home', '/var/home'].includes(fs.readlinkSync(file))) return false;
    return ['/', '/var', '/var/home'].every(dir => {
        const item = stat(dir);
        return item && item.isDirectory() && !item.isSymbolicLink() && item.uid === 0 && !(item.mode & 0o022);
    });
}
function absolute(file) {
    if (!file || !path.isAbsolute(file) || file.split(/[\\/]/).includes('..')) fail('unsafe-path');
    const resolved = path.resolve(file);
    if (resolved === path.parse(resolved).root) fail('unsafe-path');
    return resolved;
}
function directory(file) {
    const parent = path.dirname(file);
    if (parent !== file) directory(parent);
    const st = stat(file);
    if (!st) return;
    windowsRecord(file);
    if (st.isSymbolicLink()) {
        if (!systemHomeAlias(file, st)) fail('linked-directory');
    } else {
        if (!st.isDirectory()) fail('not-directory');
        if (process.platform !== 'win32') {
            const uid = process.getuid();
            if (![0, uid].includes(st.uid) || (st.mode & 0o022) && !(st.uid === 0 && (st.mode & 0o1000))) fail('unsafe-owner-or-mode');
            if (homeInput && path.isAbsolute(homeInput) && (file === path.resolve(homeInput) || file.startsWith(path.resolve(homeInput) + path.sep)) && st.uid !== uid) fail('unsafe-owner-or-mode');
        }
    }
}
function owned(file) {
    const st = stat(file);
    if (st) windowsRecord(file, true, st.isSymbolicLink() && ['remove', 'dispose'].includes(mode));
    if (st && process.platform !== 'win32' && (st.uid !== process.getuid() || !st.isSymbolicLink() && (st.mode & 0o022))) fail('unsafe-owner-or-mode');
}
function jsonFile(file) {
    directory(path.dirname(file));
    const st = stat(file);
    if (!st) return null;
    if (!st.isFile() || st.isSymbolicLink() || st.nlink !== 1 || st.size > 1024 * 1024) fail('unsafe-metadata');
    owned(file);
    windowsTrust();
    let value;
    try { value = JSON.parse(readRegular(file).toString('utf8').replace(/^\uFEFF/, '')); }
    catch { fail('malformed-metadata'); }
    if (!object(value)) fail('malformed-metadata');
    return value;
}
function readRegular(file) {
    directory(path.dirname(file));
    const before = stat(file);
    if (!before?.isFile() || before.isSymbolicLink() || before.nlink !== 1 || before.size > 256 * 1024 * 1024) fail('unsafe-file');
    owned(file);
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK | (fs.constants.O_NOFOLLOW || 0));
    try {
        const opened = fs.fstatSync(fd);
        if (opened.dev !== before.dev || opened.ino !== before.ino || !opened.isFile() || opened.nlink !== 1) fail('changed-copy');
        const bytes = fs.readFileSync(fd), after = fs.fstatSync(fd);
        if (after.size !== before.size || after.mtimeMs !== before.mtimeMs || bytes.length !== before.size) fail('changed-copy');
        return bytes;
    } finally { fs.closeSync(fd); }
}
function fingerprint(file) {
    directory(path.dirname(file));
    const st = stat(file);
    if (!st) return null;
    owned(file);
    const identity = [st.dev, st.ino, st.mode, st.nlink, st.mtimeMs];
    if (st.isSymbolicLink()) identity.push(fs.readlinkSync(file));
    else if (st.isDirectory()) identity.push(fs.readdirSync(file).sort().map(name => [name, fingerprint(path.join(file, name))]));
    else if (st.isFile()) identity.push(crypto.createHash('sha256').update(readRegular(file)).digest('hex'));
    else fail('unsupported-file');
    return JSON.stringify(identity);
}
function copySnapshot(source, target) {
    copiedTree(source);
    const st = stat(source);
    if (st.isDirectory()) {
        fs.mkdirSync(target, {mode: st.mode & 0o777});
        for (const name of fs.readdirSync(source)) copySnapshot(path.join(source, name), path.join(target, name));
    } else fs.writeFileSync(target, readRegular(source), {flag: 'wx', mode: st.mode & 0o777});
}
function ensureDirectory(file, created) {
    directory(file);
    if (stat(file)) { owned(file); return; }
    ensureDirectory(path.dirname(file), created);
    fs.mkdirSync(file, {mode: 0o700});
    created.push({file, dev: stat(file).dev, ino: stat(file).ino});
}
function snapshotDirectories(files) {
    const result = new Map();
    for (const file of files) {
        let dir = path.dirname(file);
        while (true) {
            const st = stat(dir);
            result.set(dir, st ? JSON.stringify([st.dev, st.ino, st.mode, st.uid, st.gid, st.isSymbolicLink() ? fs.readlinkSync(dir) : null]) : null);
            if (dir === path.dirname(dir)) break;
            dir = path.dirname(dir);
        }
    }
    return result;
}
function unchangedDirectories(previous) {
    for (const [dir, identity] of previous) {
        directory(dir);
        if (snapshotDirectories([path.join(dir, 'unused')]).get(dir) !== identity) fail('changed-directory');
    }
}
function transaction(home, changes, verify) {
    const records = changes.map(change => ({...change, before: Object.hasOwn(change, 'before') ? change.before : fingerprint(change.file)}));
    const created = [], lock = path.join(home, '.agents/.setup-impeccable.lock');
    let locked = false, committed = false, recovering = false;
    const parents = new Map();
    const recheckParents = file => {
        directory(path.dirname(file));
        for (const [dir, previous] of parents) {
            const current = stat(dir);
            if (!current || current.dev !== previous.dev || current.ino !== previous.ino || current.mode !== previous.mode ||
                current.uid !== previous.uid || current.gid !== previous.gid || !current.isDirectory() && !systemHomeAlias(dir, current)) fail('changed-directory');
        }
    };
    try {
        ensureDirectory(path.dirname(lock), created);
        const fd = fs.openSync(lock, 'wx', 0o600);
        fs.closeSync(fd); locked = true;
        for (const record of records) {
            ensureDirectory(path.dirname(record.file), created);
            let dir = path.dirname(record.file);
            while (dir !== path.dirname(dir)) {
                if (!parents.has(dir)) parents.set(dir, stat(dir));
                dir = path.dirname(dir);
            }
            if (fs.readdirSync(path.dirname(record.file)).some(name => /^\.setup-impeccable-[a-f0-9-]+\.(?:old|new)$/.test(name))) fail('recovery-required');
        }
        for (const record of records) {
            recheckParents(record.file);
            if (fingerprint(record.file) !== record.before) fail('changed-copy');
            const stem = path.join(path.dirname(record.file), '.setup-impeccable-' + crypto.randomUUID());
            record.backup = stem + '.old'; record.temporary = stem + '.new';
            if (record.source) {
                record.sourceBefore = fingerprint(record.source);
                copySnapshot(record.source, record.temporary);
                if (fingerprint(record.source) !== record.sourceBefore || !sameTree(record.source, record.temporary)) fail('changed-copy');
            } else if (record.bytes) {
                fs.writeFileSync(record.temporary, record.bytes, {flag: 'wx', mode: stat(record.file)?.mode & 0o777 || 0o600});
            }
            record.expectedAfter = fingerprint(record.temporary);
        }
        windowsTrust();
        for (const record of records) {
            recheckParents(record.file);
            if (fingerprint(record.file) !== record.before || record.source && fingerprint(record.source) !== record.sourceBefore) fail('changed-copy');
            if (record.before !== null) { fs.renameSync(record.file, record.backup); record.saved = true; }
            if (record.expectedAfter !== null) {
                fs.renameSync(record.temporary, record.file); record.promoted = true;
                if (fingerprint(record.file) !== record.expectedAfter) fail('changed-copy');
            }
        }
        if (verify) verify();
        windowsTrust();
        committed = true;
        for (const record of records) if (record.saved) remove(record.backup);
    } catch (error) {
        if (!committed) for (const record of records.toReversed()) {
            try {
                recheckParents(record.file);
                if (record.promoted) {
                    if (fingerprint(record.file) !== record.expectedAfter) fail('changed-copy');
                    remove(record.file);
                }
                if (record.saved) {
                    if (stat(record.file) || fingerprint(record.backup) !== record.before) fail('changed-copy');
                    fs.renameSync(record.backup, record.file);
                }
            } catch { recovering = true; }
        }
        else recovering = true;
        if (recovering) fail('recovery-required');
        throw error;
    } finally {
        for (const record of records) if (record.temporary && stat(record.temporary)) {
            try { remove(record.temporary); } catch { recovering = true; }
        }
        if (locked && !recovering) fs.unlinkSync(lock);
        if (!committed && !recovering) for (const {file, dev, ino} of created.toReversed()) {
            const st = stat(file);
            if (st?.dev === dev && st.ino === ino && fs.readdirSync(file).length === 0) fs.rmdirSync(file);
        }
        if (recovering) fail('recovery-required');
    }
}
function jsonChange(file, value) {
    const bytes = Buffer.from(JSON.stringify(value, null, 2) + '\n');
    return stat(file) && readRegular(file).equals(bytes) ? [] : [{file, bytes}];
}
function removable(file) {
    directory(path.dirname(file));
    const st = stat(file);
    if (!st) return;
    owned(file);
    if (st.isSymbolicLink()) return;
    if (st.isDirectory()) {
        for (const entry of fs.readdirSync(file)) removable(path.join(file, entry));
    } else if (!st.isFile()) fail('unsupported-file');
}
function remove(file) {
    removable(file);
    const st = stat(file);
    if (!st) return;
    if (st.isDirectory() && !st.isSymbolicLink()) {
        for (const entry of fs.readdirSync(file)) remove(path.join(file, entry));
        fs.rmdirSync(file);
    } else fs.unlinkSync(file);
    if (stat(file)) fail('removal-failed');
}
function copiedTree(file) {
    directory(path.dirname(file));
    const st = stat(file);
    if (!st || st.isSymbolicLink()) fail('invalid-skill-copy');
    owned(file);
    if (st.isDirectory()) {
        for (const entry of fs.readdirSync(file)) copiedTree(path.join(file, entry));
    } else if (!st.isFile() || st.nlink !== 1) fail('invalid-skill-copy');
}
function sameTree(left, right) {
    const a = stat(left), b = stat(right);
    if (!a || !b || a.isSymbolicLink() || b.isSymbolicLink()) return false;
    if (a.isFile() && b.isFile()) return readRegular(left).equals(readRegular(right));
    if (!a.isDirectory() || !b.isDirectory()) return false;
    const names = fs.readdirSync(left).sort(), other = fs.readdirSync(right).sort();
    return JSON.stringify(names) === JSON.stringify(other) && names.every(name => sameTree(path.join(left, name), path.join(right, name)));
}
function payloadDigest(file) {
    copiedTree(file);
    windowsTrust();
    const hash = crypto.createHash('sha256');
    const walk = (item, relative) => {
        if (stat(item).isDirectory()) {
            hash.update(JSON.stringify(['directory', relative]));
            for (const name of fs.readdirSync(item).sort()) walk(path.join(item, name), relative + '/' + name);
        } else {
            const bytes = readRegular(item);
            hash.update(JSON.stringify(['file', relative, bytes.length])); hash.update(bytes);
        }
    };
    walk(file, '');
    return hash.digest('hex');
}
const officialHelperNames = ['manual-edit-applier', 'asset-producer', 'documenter', 'finish-reviewer'];
function helperPath(profile, name) {
    return path.join(profile, 'agents', 'impeccable-' + name + '.md');
}
const references = ['routing', 'init', 'craft', 'critique', 'layout', 'typeset', 'colorize', 'polish', 'audit',
    'audit.native', 'adapt', 'adapt.native', 'animate', 'bolder', 'clarify', 'delight', 'distill', 'document',
    'extract', 'generate', 'harden', 'onboard', 'optimize', 'quieter', 'shape', 'visualize', 'overdrive',
    'doctor', 'live', 'live-setup', 'operate', 'new-work', 'craft-floor', 'component-review', 'region-map',
    'mode-operate', 'mode-persuade', 'mode-read', 'ios', 'android', 'hooks',
    ...officialHelperNames.map(name => 'degraded/' + name)];
const resources = ['scripts/impeccable', 'scripts/impeccable.cmd', 'scripts/VERSION', 'scripts/command-metadata.json',
    'scripts/live-browser.js', 'scripts/live-browser-session.js', 'scripts/live-browser-ignores.js',
    'scripts/live-browser-dom.js', 'scripts/modern-screenshot.umd.js', 'scripts/data/font-index.json', 'scripts/data/font-index-failures.json'];
function nativeTarget() {
    if (!['linux', 'darwin', 'win32'].includes(process.platform) || !['x64', 'arm64'].includes(process.arch) ||
        process.platform === 'win32' && process.arch !== 'x64') fail('unsupported-artifact');
    return (process.platform === 'win32' ? 'windows' : process.platform) + '-' + process.arch;
}
function skillIdentity(md) {
    const normalized = md.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
    const frontmatter = normalized.match(/^---\n([\s\S]*?)\n---(?:\n|$)/)?.[1];
    if (!frontmatter || frontmatter.length > 65536 || /[\x00-\x09\x0b\x0c\x0e-\x1f\x7f-\x9f\uFEFF]/.test(frontmatter)) fail('invalid-skill-identity');
    const fields = new Map();
    let parent = '';
    const scalar = input => {
        const value = input.trim();
        if (!value) fail('invalid-skill-identity');
        if (value.startsWith('"')) {
            try {
                const parsed = JSON.parse(value);
                if (typeof parsed === 'string') return parsed;
            } catch {}
            fail('invalid-skill-identity');
        }
        if (value.startsWith("'")) {
            if (!/^'(?:[^']|'')*'$/.test(value)) fail('invalid-skill-identity');
            return value.slice(1, -1).replaceAll("''", "'");
        }
        if (/^[-?:,\[\]{}#&*!|>%@`]|:(?:\s|$)|\s#/.test(value)) fail('invalid-skill-identity');
        if (/^(?:null|Null|NULL|~)$/.test(value)) return null;
        if (/^(?:true|True|TRUE)$/.test(value)) return true;
        if (/^(?:false|False|FALSE)$/.test(value)) return false;
        if (/^\+?0[box]/i.test(value)) fail('invalid-skill-identity');
        if (/^\+?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(value) || /^\+?\.(?:inf|nan)$/i.test(value)) return Number(value);
        return value;
    };
    for (const line of frontmatter.split('\n')) {
        if (!line.trim() || line.trim().startsWith('#')) continue;
        const top = line.match(/^([A-Za-z][A-Za-z0-9_-]*):(?: +(.*))?$/);
        if (top) {
            const [, name, value] = top;
            if (fields.has(name)) fail('invalid-skill-identity');
            parent = name;
            if (name === 'metadata' || name === 'allowed-tools') {
                if (value?.trim()) fail('invalid-skill-identity');
                fields.set(name, name === 'metadata' ? new Map() : []);
            } else fields.set(name, scalar(value || ''));
            continue;
        }
        const metadata = parent === 'metadata' && line.match(/^  ([A-Za-z][A-Za-z0-9_-]*): +(.+)$/);
        if (metadata) {
            const record = fields.get(parent);
            if (record.has(metadata[1])) fail('invalid-skill-identity');
            record.set(metadata[1], scalar(metadata[2]));
            continue;
        }
        const tool = parent === 'allowed-tools' && line.match(/^  - +(.+)$/);
        if (tool) {
            const value = scalar(tool[1]);
            if (typeof value !== 'string' || !value.trim()) fail('invalid-skill-identity');
            fields.get(parent).push(value);
            continue;
        }
        fail('invalid-skill-identity');
    }
    const description = fields.get('description');
    const nestedVersion = fields.get('metadata')?.get('version');
    const version = fields.has('version') ? fields.get('version') : nestedVersion;
    if (fields.get('name') !== 'impeccable' || typeof description !== 'string' || !description.trim() || description.length > 1024 ||
        !semver(version) || fields.has('version') && nestedVersion !== undefined && version !== nestedVersion) fail('invalid-skill-identity');
    return version;
}
function validateSkill(skill, target, provider) {
    copiedTree(skill);
    windowsTrust();
    const binary = 'scripts/bin/' + target + '/impeccable' + (process.platform === 'win32' ? '.exe' : '');
    const agentFiles = provider === 'codex' ? ['agents/openai.yaml', ...officialHelperNames
        .map(name => 'agents/impeccable_' + name.replaceAll('-', '_') + '.toml')] : [];
    const files = ['SKILL.md', ...references.map(name => 'reference/' + name + '.md'), ...resources, ...agentFiles, binary];
    for (const file of files) {
        const item = stat(path.join(skill, file));
        if (!item?.isFile() || item.size === 0 || item.nlink !== 1) fail('incomplete-payload');
    }
    const md = readRegular(path.join(skill, 'SKILL.md')).toString('utf8');
    const version = skillIdentity(md);
    const engine = readRegular(path.join(skill, 'scripts/VERSION')).toString('utf8').trim();
    if (!semver(engine)) fail('invalid-engine-version');
    for (const resource of resources.filter(file => file.endsWith('.json'))) {
        try { JSON.parse(readRegular(path.join(skill, resource)).toString('utf8')); }
        catch { fail('invalid-resource-json'); }
    }
    if (process.platform !== 'win32' && [path.join(skill, 'scripts/impeccable'), path.join(skill, 'scripts/bin', target, 'impeccable')]
        .some(file => !(stat(file).mode & 0o100))) fail('nonexecutable-payload');
    return {engine, version,
        checksum: crypto.createHash('sha256').update(readRegular(path.join(skill, binary))).digest('hex')};
}
function engineChecksum(version, target) {
    const asset = 'impeccable-' + target + (process.platform === 'win32' ? '.exe' : '');
    const original = 'https://github.com/pbakaus/impeccable/releases/download/engine-v' + version + '/' + asset + '.sha256';
    const fetch = (url, redirects = 0) => new Promise((resolve, reject) => {
        const parsed = new URL(url);
        if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.port ||
            !(url === original || redirects === 1 && parsed.hostname === 'release-assets.githubusercontent.com')) {
            reject(new Error('checksum-unavailable')); return;
        }
        const request = https.get(url, {rejectUnauthorized: true}, response => {
            if ([301, 302, 303, 307, 308].includes(response.statusCode) && redirects === 0 && response.headers.location) {
                response.resume(); fetch(new URL(response.headers.location, url).href, 1).then(resolve, reject); return;
            }
            if (response.statusCode !== 200) { response.resume(); reject(new Error('checksum-unavailable')); return; }
            let text = '';
            response.on('data', bytes => {
                text += bytes.toString('utf8');
                if (text.length > 4096) request.destroy(new Error('checksum-unavailable'));
            });
            response.on('error', () => reject(new Error('checksum-unavailable')));
            response.on('end', () => {
                const match = text.trim().match(/^([a-f0-9]{64})(?:\s+\*?([a-zA-Z0-9.-]+))?$/i);
                if (!match || match[2] && match[2] !== asset) reject(new Error('checksum-unavailable'));
                else resolve(match[1].toLowerCase());
            });
        });
        const timer = setTimeout(() => request.destroy(new Error('checksum-unavailable')), 30000);
        request.on('close', () => clearTimeout(timer));
        request.on('error', () => reject(new Error('checksum-unavailable')));
    });
    return fetch(original);
}
function stagePath(input) {
    const stage = absolute(input), tempRoot = fs.realpathSync(os.tmpdir());
    if (path.dirname(stage) !== tempRoot || !/^setup-impeccable-[a-zA-Z0-9]+$/.test(path.basename(stage))) fail('unsafe-stage');
    directory(tempRoot);
    return stage;
}
function matchesSkill(file, pattern, base, exact = false) {
    const posix = value => value.split(path.sep).join('/');
    const parent = path.dirname(file);
    const candidates = [file, parent, path.relative(base, file), path.relative(base, parent)].map(posix);
    if (exact) return candidates.includes(posix(pattern.replace(/^\.[\\/]/, '')));
    candidates.push('SKILL.md', path.basename(parent));
    const value = posix(pattern);
    if (/[\\\[\]{}()]/.test(value) || value.startsWith('!') || value.length > 4096) fail('unverified-resource-selection');
    if (!value || value.startsWith('#')) return false;
    const parts = value.split(/\/+/);
    if (parts.includes('..') || parts.length > 256) fail('unverified-resource-selection');
    const expressions = parts.map(part => part === '**' ? null : new RegExp('^' + part
        .replace(/[.+^$|]/g, '\\$&').replace(/\*+/g, '.*').replace(/\?/g, '.') + '$'));
    return candidates.some(candidate => {
        const segments = candidate.split(/\/+/);
        const match = (pi, fi) => {
            if (pi === parts.length) return fi === segments.length;
            if (parts[pi] === '**') return match(pi + 1, fi) || fi < segments.length &&
                !segments[fi].startsWith('.') && match(pi, fi + 1);
            if (fi === segments.length || segments[fi].startsWith('.') && !parts[pi].startsWith('.') ||
                !segments[fi] && /[*?]/.test(parts[pi])) return false;
            return expressions[pi].test(segments[fi]) && match(pi + 1, fi + 1);
        };
        return match(0, 0);
    });
}
function enabledSkill(file, entries, profile) {
    let enabled = !entries.filter(entry => entry.startsWith('!')).some(entry => matchesSkill(file, entry.slice(1), profile));
    if (entries.filter(entry => entry.startsWith('+')).some(entry => matchesSkill(file, entry.slice(1), profile, true))) enabled = true;
    if (entries.filter(entry => entry.startsWith('-')).some(entry => matchesSkill(file, entry.slice(1), profile, true))) enabled = false;
    return enabled;
}
function ignoredPiDescriptor(file, profile, skillDirectory = path.dirname(file)) {
    const rules = [];
    const addRules = (directoryPath, prefix) => {
        for (const name of ['.gitignore', '.ignore', '.fdignore']) {
            const policy = path.join(directoryPath, name);
            if (!stat(policy)) continue;
            for (let line of readRegular(policy).toString('utf8').split(/\r?\n/)) {
                if (!line.trim() || line.trim().startsWith('#')) continue;
                const negated = line.startsWith('!');
                if (negated) line = line.slice(1);
                line = line.replace(/^\//, '').replace(/[ \t]+$/, '');
                if (!line) continue;
                if (/[\\\[\]]/.test(line) || line.startsWith('!') || line.length > 4096) fail('unverified-resource-selection');
                const directoryOnly = line.endsWith('/');
                const pattern = prefix + line.replace(/\/$/, '');
                const anchored = pattern.includes('/');
                const parts = pattern.split('/');
                if (parts.includes('..') || parts.includes('.') || parts.length > 256) fail('unverified-resource-selection');
                let expression = '';
                for (let index = 0; index < parts.length; index++) {
                    const part = parts[index];
                    if (part === '**') {
                        expression += index === parts.length - 1 ? '.*' : '(?:[^/]+/)*';
                    } else {
                        expression += part.replace(/[.+^$|(){}]/g, '\\$&').replace(/\*+/g, '[^/]*').replace(/\?/g, '[^/]');
                        if (index < parts.length - 1) expression += '/';
                    }
                }
                rules.push({negated, directoryOnly, expression: new RegExp((anchored ? '^' : '(?:^|/)') + expression + '$', 'i')});
            }
        }
    };
    const ignored = (relative, isDirectory) => {
        let result = false;
        for (const rule of rules) if ((!rule.directoryOnly || isDirectory) && rule.expression.test(relative)) result = !rule.negated;
        return result;
    };
    const root = path.join(profile, 'skills');
    addRules(root, '');
    const rootDescriptor = stat(path.join(root, 'SKILL.md'));
    if ((rootDescriptor?.isFile() || rootDescriptor?.isSymbolicLink()) && !ignored('SKILL.md', false)) return true;
    if (ignored('impeccable', true)) return true;
    addRules(skillDirectory, 'impeccable/');
    return ignored('impeccable/SKILL.md', false);
}
function discoveryIntent(home, selected, skillDirectory) {
    const direct = path.join(selected.profile, 'skills/impeccable/SKILL.md');
    const shared = path.join(home, '.agents/skills/impeccable/SKILL.md');
    const exclusion = '!' + path.dirname(shared) + '/**';
    const entries = [...(selected.data.skills || []), exclusion];
    if (!enabledSkill(direct, entries, selected.profile) || enabledSkill(shared, entries, path.join(home, '.agents')) ||
        ignoredPiDescriptor(direct, selected.profile, skillDirectory)) fail('pi-discovery-conflict');
    return exclusion;
}
function context(excluded = false) {
    if (blocked === '1') fail('pi-profiles-blocked');
    const home = absolute(homeInput);
    directory(home); owned(home);
    const lock = path.join(home, '.agents/.setup-impeccable.lock');
    directory(path.dirname(lock));
    if (stat(lock)) fail('recovery-required');
    const profile = (value, fallback) => {
        const result = absolute(value || path.join(home, fallback));
        if (result === home) fail('unsafe-path');
        directory(result); owned(result);
        return result;
    };
    const activePi = absolute(activePiInput || path.join(home, '.pi/agent'));
    const piRelative = path.relative(home, activePi);
    if (!piRelative || piRelative === '..' || piRelative.startsWith('..' + path.sep) || path.isAbsolute(piRelative)) fail('outside-home');
    const pi = unique([path.join(home, '.pi/agent'), profile(activePi, '.pi/agent')]);
    const claude = profile(process.env.CLAUDE_CONFIG_DIR, '.claude');
    const bindings = [
        {provider: 'claude', source: '.claude/skills/impeccable', destination: path.join(claude, 'skills/impeccable')},
        {provider: 'codex', source: '.agents/skills/impeccable', destination: path.join(home, '.agents/skills/impeccable')},
        {provider: 'cursor', source: '.cursor/skills/impeccable', destination: path.join(home, '.cursor/skills/impeccable')},
        {provider: 'gemini', source: '.gemini/skills/impeccable', destination: path.join(home, '.gemini/skills/impeccable')},
        {provider: 'pi', source: '.pi/agent/skills/impeccable', destination: path.join(pi.at(-1), 'skills/impeccable')},
    ];
    const helperBindings = [{source: '.claude', destination: claude}, {source: '.cursor', destination: path.join(home, '.cursor')}]
        .flatMap(binding => officialHelperNames.map(name => ({source: helperPath(binding.source, name), destination: helperPath(binding.destination, name)})));
    const removalDirs = unique([...bindings.map(binding => path.dirname(binding.destination)), path.join(home, '.claude/skills'), path.join(home, '.codex/skills'),
        path.join(profile(process.env.CODEX_HOME, '.codex'), 'skills'), ...pi.map(dir => path.join(dir, 'skills'))]);
    const removalHelpers = unique([path.join(home, '.claude'), claude, path.join(home, '.cursor')])
        .flatMap(dir => officialHelperNames.map(name => helperPath(dir, name)));
    const removals = removalDirs.map(dir => path.join(dir, 'impeccable'))
        .concat(pi.map(dir => path.join(dir, 'skills/impeccable.md')), removalHelpers);
    if (excluded) removals.forEach(removable);
    else for (const {destination} of [...bindings, ...helperBindings]) {
        const directoryPath = path.dirname(destination);
        directory(directoryPath); owned(directoryPath);
        if (stat(destination)) copiedTree(destination);
    }
    const settings = pi.map(dir => {
        directory(dir); owned(dir);
        const file = path.join(dir, 'settings.json');
        const data = jsonFile(file) || {};
        if (data.skills !== undefined && (!Array.isArray(data.skills) || !data.skills.every(value => typeof value === 'string'))) fail('invalid-settings');
        return {file, data, profile: dir};
    });
    const manifestFile = path.join(home, '.agents/.setup-impeccable.json');
    if (!excluded) {
        const scopes = [...bindings, ...helperBindings].map(binding => binding.destination).concat(settings.map(record => record.file), manifestFile)
            .map(file => process.platform === 'win32' ? file.replaceAll('\\', '/').toLowerCase() : file);
        if (new Set(scopes).size !== scopes.length || scopes.some((left, index) => scopes.some((right, other) => index !== other && left.startsWith(right + '/')))) fail('conflicting-profile-scope');
    }
    const manifest = jsonFile(manifestFile) || {version: 1, source: 'pbakaus/impeccable', ownedExclusions: {}};
    if (manifest.version !== 1 || manifest.source !== 'pbakaus/impeccable' || !object(manifest.ownedExclusions) ||
        !Object.entries(manifest.ownedExclusions).every(([dir, items]) => {
            if (typeof dir !== 'string' || !path.isAbsolute(dir) || dir.split(/[\\/]/).includes('..') || !dir.startsWith(home + path.sep)) return false;
            const allowed = ['!' + path.join(home, '.agents/skills/impeccable') + '/**', '!' + path.join(dir, 'skills/impeccable') + '/**'];
            return Array.isArray(items) && items.every(item => allowed.includes(item));
        })) fail('invalid-inventory');
    if (manifest.piCopy !== undefined && (!object(manifest.piCopy) || typeof manifest.piCopy.profile !== 'string' ||
        !manifest.piCopy.profile.startsWith(home + path.sep) || !/^[a-f0-9]{64}$/.test(manifest.piCopy.snapshot))) fail('invalid-inventory');
    const directPi = bindings.find(binding => binding.provider === 'pi').destination;
    if (!excluded && manifest.piCopy?.profile === pi.at(-1) && stat(directPi) && payloadDigest(directPi) !== manifest.piCopy.snapshot) fail('modified-pi-copy');
    for (const dir of unique([...bindings, ...helperBindings].map(binding => path.dirname(binding.destination))
        .concat(settings.map(record => path.dirname(record.file)), path.dirname(manifestFile)))) {
        directory(dir);
        if (stat(dir) && fs.readdirSync(dir).some(name => /^\.setup-impeccable-[a-f0-9-]+\.(?:old|new)$/.test(name))) fail('recovery-required');
    }
    if (!excluded) discoveryIntent(home, settings.at(-1));
    windowsTrust();
    return {home, pi, bindings, helperBindings, removals, settings, manifestFile, manifest};
}
async function run() {
    if (mode === 'dispose') {
        const stage = stagePath(stageInput);
        const st = stat(stage);
        if (st) {
            if (!st.isSymbolicLink() && (!st.isDirectory() || process.platform !== 'win32' && (st.mode & 0o077))) fail('unsafe-stage');
            remove(stage);
        }
    } else if (mode === 'stage') {
        const tempRoot = fs.realpathSync(os.tmpdir());
        directory(tempRoot);
        const stage = fs.mkdtempSync(path.join(tempRoot, 'setup-impeccable-'));
        for (const child of ['.tmp', '.appdata', '.localappdata', '.git']) fs.mkdirSync(path.join(stage, child), {mode: 0o700});
        process.stdout.write(stage + '\n');
    } else if (mode === 'preflight') {
        context(); nativeTarget();
    } else if (mode === 'remove') {
        const {home, removals, settings, manifestFile, manifest} = context(true);
        const changes = [];
        for (const record of settings) {
            const ownedEntries = manifest.ownedExclusions[record.profile] || [];
            if (ownedEntries.length && record.data.skills) {
                const updated = record.data.skills.filter(entry => !ownedEntries.includes(entry));
                if (updated.length !== record.data.skills.length) {
                    record.data.skills = updated;
                    changes.push(...jsonChange(record.file, record.data));
                }
            }
            delete manifest.ownedExclusions[record.profile];
        }
        changes.push(...removals.filter(file => stat(file)).map(file => ({file})));
        if (stat(manifestFile)) changes.push(...jsonChange(manifestFile, manifest));
        if (changes.length) transaction(home, changes, () => {
            if (removals.some(file => stat(file))) fail('removal-failed');
        });
    } else if (mode === 'promote') {
        const {home, bindings, helperBindings, settings, manifestFile, manifest} = context(), target = nativeTarget();
        const stage = stagePath(stageInput);
        directory(stage); owned(stage);
        if (!stat(stage)?.isDirectory() || process.platform !== 'win32' && (stat(stage).mode & 0o077)) fail('unsafe-stage');
        const skills = bindings.map(binding => {
            const source = path.join(stage, binding.source);
            return {...binding, source, payload: validateSkill(source, target, binding.provider)};
        });
        const piSkill = skills.find(binding => binding.provider === 'pi');
        const directPi = piSkill.destination;
        const sharedPi = skills.find(binding => binding.provider === 'codex').destination;
        if (manifest.piCopy?.profile !== settings.at(-1).profile && stat(directPi) &&
            !(stat(sharedPi) && sameTree(directPi, sharedPi)) && !skills.some(binding => sameTree(directPi, binding.source))) fail('unverified-pi-copy');
        const {engine, version} = piSkill.payload;
        if (skills.some(({payload}) => payload.engine !== engine || payload.version !== version)) fail('inconsistent-snapshot');
        const helpers = helperBindings.map(binding => ({...binding, source: path.join(stage, binding.source)}));
        for (const {source} of helpers) {
            copiedTree(source);
            if (!stat(source)?.isFile() || stat(source).size === 0) fail('incomplete-payload');
        }
        const artifacts = [...skills, ...helpers];
        const sourceSnapshots = new Map(artifacts.map(({source}) => [source, fingerprint(source)]));
        const destinationFiles = artifacts.map(binding => binding.destination).concat(settings.map(record => record.file), manifestFile);
        const destinationSnapshots = new Map(destinationFiles.map(file => [file, fingerprint(file)]));
        const parentSnapshots = snapshotDirectories([...sourceSnapshots.keys(), ...destinationSnapshots.keys()]);
        const checksum = await engineChecksum(engine, target);
        if (skills.some(({payload}) => payload.checksum !== checksum)) fail('engine-checksum-mismatch');
        unchangedDirectories(parentSnapshots);
        for (const [file, before] of [...sourceSnapshots, ...destinationSnapshots]) if (fingerprint(file) !== before) fail('changed-copy');
        const changes = artifacts.map(({source, destination}) => ({file: destination, source}));
        const selected = settings.at(-1);
        const exclusion = discoveryIntent(home, selected, piSkill.source);
        if (!(selected.data.skills || []).includes(exclusion)) {
            selected.data.skills = [...(selected.data.skills || []), exclusion];
            manifest.ownedExclusions[selected.profile] = unique([...(manifest.ownedExclusions[selected.profile] || []), exclusion]);
            changes.push(...jsonChange(selected.file, selected.data));
        }
        manifest.piCopy = {profile: selected.profile, snapshot: payloadDigest(piSkill.source)};
        manifest.skillVersion = version;
        manifest.engineVersion = engine;
        manifest.snapshot = crypto.createHash('sha256').update(skills.map(({source}) => readRegular(path.join(source, 'SKILL.md'))).join('\n')).digest('hex');
        changes.push(...jsonChange(manifestFile, manifest));
        for (const change of changes) change.before = destinationSnapshots.get(change.file);
        transaction(home, changes, () => {
            for (const {provider, source, destination} of skills) {
                if (validateSkill(destination, target, provider).checksum !== checksum) fail('engine-checksum-mismatch');
                if (!sameTree(source, destination)) fail('changed-copy');
            }
            for (const {source, destination} of helpers) {
                copiedTree(destination);
                if (!sameTree(source, destination)) fail('changed-copy');
            }
            discoveryIntent(home, {...selected, data: jsonFile(selected.file)});
        });
    } else fail('unknown-operation');
}
run().catch(error => {
    const allowed = ['unsafe-path', 'linked-directory', 'not-directory', 'unsafe-owner-or-mode', 'unsafe-metadata',
        'malformed-metadata', 'unsupported-file', 'removal-failed', 'invalid-skill-copy', 'incomplete-payload',
        'invalid-skill-identity', 'invalid-engine-version', 'nonexecutable-payload', 'unsupported-artifact',
        'unsafe-stage', 'pi-profiles-blocked', 'invalid-settings', 'invalid-inventory', 'pi-discovery-conflict',
        'unverified-resource-selection', 'invalid-resource-json', 'inconsistent-snapshot', 'checksum-unavailable',
        'engine-checksum-mismatch', 'modified-pi-copy', 'unverified-pi-copy', 'changed-copy', 'changed-directory', 'recovery-required', 'unsafe-file', 'outside-home', 'windows-acl-unverified', 'conflicting-profile-scope', 'unknown-operation'];
    const reason = allowed.includes(error.message) ? error.message : ['EACCES', 'EPERM', 'ENOENT', 'ENOSPC', 'EROFS', 'EBUSY'].includes(error.code) ? error.code : 'operation-failed';
    process.stderr.write('Impeccable: ' + reason + '.\n');
    process.exitCode = 1;
});
