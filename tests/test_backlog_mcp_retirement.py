#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

os.umask(0o077)
ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ["mac.sh", "ubuntu.sh", "wsl.sh", "pi.sh", "bazzite.sh"]
BEGIN = "// BEGIN BACKLOG_MCP_RETIREMENT\n"
END = "\n// END BACKLOG_MCP_RETIREMENT"

def program(path: Path) -> str:
    text = path.read_text()
    assert text.count(BEGIN) == 1 and text.count(END) == 1, path
    return text.split(BEGIN, 1)[1].split(END, 1)[0]

reference = program(ROOT / SCRIPTS[0])
for script in SCRIPTS[1:]:
    assert program(ROOT / script) == reference, f"embedded helper drifted in {script}"
assert program(ROOT / "win.ps1") == reference, "PowerShell helper drifted"

def run(home: Path, *, pi="", claude="", codex="", gemini="", ok=True, prepare=True, code=None, cwd=None, extra_env=None):
    if not home.is_symlink():
        home.chmod(0o700)
        if prepare:
            for candidate in home.rglob("*"):
                if candidate.is_dir() and not candidate.is_symlink():
                    candidate.chmod(candidate.stat().st_mode & ~0o022)
                elif candidate.is_file() and not candidate.is_symlink():
                    candidate.chmod(candidate.stat().st_mode & ~0o022)
    environment = os.environ.copy()
    environment.pop("NODE_OPTIONS", None)
    environment.pop("NODE_PATH", None)
    if extra_env:
        environment.update(extra_env)
    result = subprocess.run(
        ["node", "--input-type=commonjs", "-", str(home), pi, claude, codex, gemini],
        input=code or reference, text=True, capture_output=True, env=environment, cwd=cwd,
    )
    if ok:
        assert result.returncode == 0, (result.stdout, result.stderr)
        assert result.stdout.strip() in {"removed", "absent"}, result.stdout
    else:
        assert result.returncode != 0
        assert result.stdout.strip() in {"unsafe-path", "unsafe-home", "unsafe-profile", "unsafe-boundary", "unsafe-metadata", "malformed-metadata", "duplicate-key", "unsupported-json-number", "malformed-toml", "unsupported-toml", "toml-parser-failed", "toml-parser-unavailable", "unsafe-toml-edit", "metadata-changed", "boundary-changed", "short-write", "write-failed", "native-wrapper-required", "filesystem-error"}, (result.stdout, result.stderr)
    return result

with tempfile.TemporaryDirectory() as raw:
    root = Path(raw); home = root / "home"; home.mkdir()
    shared = home / ".config/mcp/mcp.json"; shared.parent.mkdir(parents=True)
    shared.write_text(json.dumps({"settings": {"keep": True}, "mcpServers": {
        "backlog-alias": {"command": "/usr/local/bin/backlog", "args": ["mcp", "start", "--cwd", "/repo"], "env": {"TOKEN": "secret"}},
        "keep": {"command": "keep-mcp", "args": []}}}, indent=2) + "\n")
    # Managed adapter import paths are global-only here; project-relative imports
    # are deliberately not scanned.
    for relative in [".claude/mcp.json", ".claude/claude_desktop_config.json", ".cursor/mcp.json", ".windsurf/mcp.json", ".codex/config.json"]:
        imported = home / relative; imported.parent.mkdir(parents=True, exist_ok=True)
        imported.write_text(json.dumps({"mcpServers": {"backlog": {}, "keep": {}}}) + "\n")
    claude = home / "profiles/claude"; claude.mkdir(parents=True)
    (claude / "settings.json").write_text(json.dumps({"mcpServers": {"backlog": {"url": "http://unused"}, "other": {"url": "https://example.invalid"}}, "credential": "preserve"}) + "\n")
    (claude / ".claude.json").write_text(json.dumps({"mcpServers": {"backlog": {}}, "projects": {"/repo": {"mcpServers": {"backlog": {"keep": True}}}}}) + "\n")
    gemini_root = home / "profiles/gemini"; gemini_root.mkdir(parents=True)
    (gemini_root / "settings.json").write_text(json.dumps({"mcpServers": {"backlog": {}, "other": {}}, "keep": True}) + "\n")
    pi = home / "profiles/pi"; pi.mkdir(parents=True)
    (pi / "mcp.json").write_text(json.dumps({"mcpServers": {"BackLog": {"disabled": True}}, "settings": {"keep": 1}}) + "\n")
    codex = home / "profiles/codex"; codex.mkdir(parents=True)
    (codex / "config.toml").write_text('[model]\nname = "keep"\n\n[mcp_servers.backlog]\ncommand = "/usr/local/bin/backlog"\nargs = ["mcp", "start", "--cwd", "/repo"]\n\n[mcp_servers.keep]\ncommand = "keep"\n')
    project = home / "Code/repo"; project.mkdir(parents=True)
    project_config = project / ".mcp.json"; project_text = '{"mcpServers":{"backlog":{"command":"backlog"}}}\n'; project_config.write_text(project_text)
    task = home / "backlog/config.yml"; task.parent.mkdir(); task.write_text("keep: true\n")
    result = run(home, pi=str(pi), claude=str(claude), codex=str(codex), gemini=str(gemini_root))
    assert result.stdout.strip() == "removed"
    data = json.loads(shared.read_text()); assert set(data["mcpServers"]) == {"keep"}; assert data["settings"]["keep"] is True
    for relative in [".claude/mcp.json", ".claude/claude_desktop_config.json", ".cursor/mcp.json", ".windsurf/mcp.json", ".codex/config.json"]:
        assert set(json.loads((home / relative).read_text())["mcpServers"]) == {"keep"}
    data = json.loads((claude / "settings.json").read_text()); assert set(data["mcpServers"]) == {"backlog", "other"}; assert data["credential"] == "preserve"
    selected_claude = json.loads((claude / ".claude.json").read_text()); assert selected_claude["mcpServers"] == {}; assert selected_claude["projects"]["/repo"]["mcpServers"]["backlog"]["keep"] is True
    selected_gemini = json.loads((gemini_root / "settings.json").read_text()); assert set(selected_gemini["mcpServers"]) == {"other"}; assert selected_gemini["keep"] is True
    data = json.loads((pi / "mcp.json").read_text()); assert data == {"mcpServers": {}, "settings": {"keep": 1}}
    text = (codex / "config.toml").read_text(); assert "mcp_servers.backlog" not in text and "mcp_servers.keep" in text and '[model]' in text
    assert project_config.read_text() == project_text and task.read_text() == "keep: true\n"
    assert run(home, pi=str(pi), claude=str(claude), codex=str(codex), gemini=str(gemini_root)).stdout.strip() == "absent"

with tempfile.TemporaryDirectory() as raw:
    root = Path(raw); home = root / "home"; home.mkdir(); target = root / "target.json"
    target.write_text('{"mcpServers":{"backlog":{}}}\n')
    (home / ".agents").mkdir(); os.symlink(target, home / ".agents/mcp.json")
    before = target.read_text(); run(home, ok=False); assert target.read_text() == before

with tempfile.TemporaryDirectory() as raw:
    home = Path(raw); (home / ".config/mcp").mkdir(parents=True)
    file = home / ".config/mcp/mcp.json"; text = '{"mcpServers":{"backlog":{},"backlog":{"command":"other"}}}\n'; file.write_text(text)
    run(home, ok=False); assert file.read_text() == text

# TOML syntax must be validated before any candidate is changed, and table bounds
# must not consume arrays-of-tables or text that merely resembles a header.
toml_cases = {
    "array-table": ('[mcp_servers.backlog]\ncommand = "backlog"\nargs = ["mcp", "start"]\n\n[[unrelated]]\nkeep = "yes"\n', '[[unrelated]]\nkeep = "yes"\n'),
    "multiline-string": ('custom = """\n[mcp_servers.backlog]\nthis is NOT a server\n"""\n\n[other]\nkeep = true\n', None),
    "malformed": ('[mcp_servers.backlog]\ncommand = "backlog"\ninvalid = [\n', None),
    "quoted-key": ('[mcp_servers."backlog"]\ncommand = "backlog"\nargs = ["mcp", "start"]\n\n[other]\nkeep = true\n', '[other]\nkeep = true\n'),
    "alias-nested-env": ('[mcp_servers.tasks]\ncommand = "/usr/local/bin/backlog"\nargs = ["mcp", "start"]\n[mcp_servers.tasks.env]\nTOKEN = "preserve-only-by-removal"\n\n[other]\nkeep = true\n', '[other]\nkeep = true\n'),
    "inline": ('mcp_servers = { backlog = { command = "backlog", args = ["mcp", "start"] } }\n[other]\nkeep = true\n', None),
    "dotted": ('mcp_servers.backlog.command = "backlog"\nmcp_servers.backlog.args = ["mcp", "start"]\n[other]\nkeep = true\n', None),
    "duplicate": ('[mcp_servers.backlog]\ncommand = "backlog"\ncommand = "other"\n', None),
}
for name, (text, preserved) in toml_cases.items():
    with tempfile.TemporaryDirectory() as raw:
        home = Path(raw); file = home / ".codex/config.toml"; file.parent.mkdir(parents=True); file.write_text(text)
        result = run(home, ok=name not in {"malformed", "duplicate", "inline", "dotted"})
        if name in {"multiline-string"}:
            assert result.stdout.strip() == "absent" and file.read_text() == text
        elif preserved is not None:
            assert preserved in file.read_text()
        else:
            assert file.read_text() == text

# Source-span removal preserves unrelated numeric literals without normalization.
for number in ["9007199254740993", "1e400", "1.0000000000000001", "0.25", "-0"]:
    with tempfile.TemporaryDirectory() as raw:
        home = Path(raw); file = home / ".config/mcp/mcp.json"; file.parent.mkdir(parents=True)
        text = '{"unrelated":' + number + ',"mcpServers":{"backlog":{},"keep":{}}}\n'; file.write_text(text)
        run(home); assert file.read_text() == text.replace('"backlog":{},', '')

# Native compatibility imports use their own top-level server-map spellings.
with tempfile.TemporaryDirectory() as raw:
    home = Path(raw)
    for relative, key in [('.codex/config.json', 'mcp_servers'), ('.cursor/mcp.json', 'mcp-servers'), ('.windsurf/mcp.json', 'mcp-servers')]:
        file = home / relative; file.parent.mkdir(parents=True)
        file.write_text(json.dumps({key: {'backlog': {}, 'keep': {}}, 'projects': {'backlog': {'keep': True}}}))
    run(home)
    for relative, key in [('.codex/config.json', 'mcp_servers'), ('.cursor/mcp.json', 'mcp-servers'), ('.windsurf/mcp.json', 'mcp-servers')]:
        value = json.loads((home / relative).read_text())
        assert set(value[key]) == {'keep'} and value['projects']['backlog']['keep']

# Python must run isolated from cwd, PYTHONPATH, and startup hooks.
with tempfile.TemporaryDirectory() as raw:
    root = Path(raw); home = root / "home"; home.mkdir(); codex = home / ".codex/config.toml"; codex.parent.mkdir(parents=True)
    codex.write_text('[mcp_servers.backlog]\ncommand="backlog"\nargs=["mcp","start"]\n')
    poison = root / "poison"; poison.mkdir(); sentinel = root / "executed"
    (poison / "sitecustomize.py").write_text(f'from pathlib import Path\nPath({str(sentinel)!r}).write_text("site")\n')
    (poison / "tomllib.py").write_text(f'from pathlib import Path\nPath({str(sentinel)!r}).write_text("shadow")\nraise RuntimeError("shadowed")\n')
    result = run(home, cwd=poison, extra_env={"PYTHONPATH": str(poison)})
    assert result.stdout.strip() == "removed" and not sentinel.exists()

# A legacy system Python without tomllib falls back to a verified managed
# runtime, without PATH shims, project pins, or changing the caller's selection.
with tempfile.TemporaryDirectory() as raw:
    home = Path(raw)
    codex = home / '.codex/config.toml'; codex.parent.mkdir()
    original = '[mcp_servers.keep]\ncommand="keep"\n'; codex.write_text(original)
    runtime = home / '.pyenv/versions/3.12.77/bin/python3'; runtime.parent.mkdir(parents=True)
    runtime.symlink_to('/usr/bin/python3')
    prelude = r'''const fixtureFs=require('node:fs'), fixtureProcess=require('node:child_process');
const fixtureStat=fixtureFs.lstatSync.bind(fixtureFs), fixtureSpawn=fixtureProcess.spawnSync.bind(fixtureProcess);
fixtureFs.lstatSync=(file,...args)=>{if(['/opt/homebrew/bin/python3','/usr/local/bin/python3'].includes(file)){const e=new Error(); e.code='ENOENT'; throw e;} return fixtureStat(file,...args);};
let fixtureProbe=0;
fixtureProcess.spawnSync=(command,args,options)=>{if(args.includes('import tomllib; print("ready")') && ++fixtureProbe===1) return {status:1,stdout:'',stderr:'fixture: no tomllib'}; return fixtureSpawn(command,args,options);};
'''
    assert run(home, code=prelude + reference).stdout.strip() == 'absent'
    assert codex.read_text() == original and runtime.is_symlink()

# Native group-writable defaults are a valid absent no-op, but a selected
# registration under the same mutation boundary is refused without changes.
with tempfile.TemporaryDirectory() as raw:
    home = Path(raw); directory = home / ".config/mcp"; directory.mkdir(parents=True); os.chmod(home / ".config", 0o775); os.chmod(directory, 0o775)
    file = directory / "mcp.json"; file.write_text('{"mcpServers":{"keep":{}}}\n'); file.chmod(0o664)
    assert run(home, prepare=False).stdout.strip() == "absent"
    text = '{"mcpServers":{"backlog":{},"keep":{}}}\n'; file.write_text(text); file.chmod(0o664)
    run(home, ok=False, prepare=False); assert file.read_text() == text

# Preflight is all-or-nothing across candidates, and in-place descriptor writes
# preserve the credential-bearing file's mode and inode.
with tempfile.TemporaryDirectory() as raw:
    home = Path(raw); shared = home / ".config/mcp/mcp.json"; shared.parent.mkdir(parents=True)
    shared.write_text('{"mcpServers":{"backlog":{},"keep":{}}}\n'); shared.chmod(0o600)
    before_inode = shared.stat().st_ino; codex = home / ".codex/config.toml"; codex.parent.mkdir(); codex.write_text('[mcp_servers.backlog]\ninvalid = [\n')
    before = shared.read_text(); run(home, ok=False)
    assert shared.read_text() == before and shared.stat().st_ino == before_inode and (shared.stat().st_mode & 0o777) == 0o600
    codex.write_text('[other]\nkeep=true\n'); run(home)
    assert shared.stat().st_ino == before_inode and (shared.stat().st_mode & 0o777) == 0o600

# A linked HOME, hardlinked/oversized files, and unsafe writable ancestors fail
# before any other candidate is changed.
with tempfile.TemporaryDirectory() as raw:
    root = Path(raw); actual = root / "actual"; actual.mkdir(); alias = root / "alias"; alias.symlink_to(actual, target_is_directory=True)
    run(alias, ok=False)
with tempfile.TemporaryDirectory() as raw:
    home = Path(raw); shared = home / ".config/mcp/mcp.json"; shared.parent.mkdir(parents=True)
    shared.write_text('{"mcpServers":{"backlog":{}}}\n'); linked = home / "copy"; os.link(shared, linked)
    before = shared.read_text(); run(home, ok=False); assert shared.read_text() == before
with tempfile.TemporaryDirectory() as raw:
    home = Path(raw); shared = home / ".config/mcp/mcp.json"; shared.parent.mkdir(parents=True)
    shared.write_text(" " * (2 * 1024 * 1024 + 1)); run(home, ok=False)
with tempfile.TemporaryDirectory() as raw:
    home = Path(raw); unsafe = home / ".config"; unsafe.mkdir(mode=0o777); os.chmod(unsafe, 0o777)
    shared = unsafe / "mcp/mcp.json"; shared.parent.mkdir(); shared.write_text('{"mcpServers":{"backlog":{}}}\n')
    before = shared.read_text(); run(home, ok=False, prepare=False); assert shared.read_text() == before

# A simulated Bazzite boundary accepts only the documented root-owned exact
# /home alias; the production flow must inspect the logical boundary first.
assert "logicalBoundary = safeBoundary(logicalHome)" in reference
alias_code = reference[reference.index("function trustedHomeAlias"):reference.index("function jsonDocument")]
alias_fixture = r'''const path=require('node:path');
const directory=(uid=0,mode=0o40755)=>({uid,mode,isDirectory:()=>true,isSymbolicLink:()=>false});
let target='/var/home'; const map={'/':directory(),'/var':directory(),'/var/home':directory(),'/home':{uid:0,mode:0o120777,isDirectory:()=>false,isSymbolicLink:()=>true}};
const fs={lstatSync:file=>map[file],readlinkSync:()=>target}; const info=file=>map[file]||null;
''' + alias_code + r'''
if(!trustedHomeAlias('/home',map['/home'])) process.exit(1); target='/tmp/home'; if(trustedHomeAlias('/home',map['/home'])) process.exit(2); map['/home'].uid=1000; target='/var/home'; if(trustedHomeAlias('/home',map['/home'])) process.exit(3);
'''
subprocess.run(["node", "-e", alias_fixture], check=True)

# Short descriptor writes are completed in a loop rather than truncating output.
with tempfile.TemporaryDirectory() as raw:
    home = Path(raw); file = home / ".config/mcp/mcp.json"; file.parent.mkdir(parents=True)
    file.write_text('{"mcpServers":{"backlog":{},"keep":{}}}\n')
    prelude = "const shortFs=require('node:fs'); const realWrite=shortFs.writeSync.bind(shortFs); shortFs.writeSync=(fd,buffer,offset,length,position)=>realWrite(fd,buffer,offset,Math.min(length,3),position);\n"
    run(home, code=prelude + reference)
    assert set(json.loads(file.read_text())["mcpServers"]) == {"keep"}

# Swap a second candidate on its already-open inode during the final bounded
# reread. No candidate may be written after the mismatch is detected.
with tempfile.TemporaryDirectory() as raw:
    home = Path(raw); first = home / ".config/mcp/mcp.json"; first.parent.mkdir(parents=True)
    second = home / ".agents/mcp.json"; second.parent.mkdir(parents=True)
    original = '{"mcpServers":{"backlog":{},"keep":{}}}\n'; swapped = '{"mcpServers":{"otherxx":{},"keep":{}}}\n'
    assert len(original) == len(swapped)
    first.write_text(original); second.write_text(original)
    prelude = r'''const fixtureFs=require('node:fs');
const fixtureOriginal={openSync:fixtureFs.openSync.bind(fixtureFs),readSync:fixtureFs.readSync.bind(fixtureFs),writeFileSync:fixtureFs.writeFileSync.bind(fixtureFs)};
const fixtureReads=new Map(); let fixtureInjected=false;
fixtureFs.readSync=function(fd,...args){const count=(fixtureReads.get(fd)||0)+1; fixtureReads.set(fd,count); if(!fixtureInjected && count===2){fixtureInjected=true; fixtureOriginal.writeFileSync(process.env.BACKLOG_SWAP_TARGET,process.env.BACKLOG_SWAP_TEXT);} return fixtureOriginal.readSync(fd,...args);};
'''
    run(home, ok=False, code=prelude + reference, extra_env={"BACKLOG_SWAP_TARGET": str(second), "BACKLOG_SWAP_TEXT": swapped})
    assert first.read_text() == original and second.read_text() == swapped

print("✓ Backlog MCP retirement fixtures passed")
