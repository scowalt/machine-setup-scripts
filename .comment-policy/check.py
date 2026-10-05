import argparse
import ast
import hashlib
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from tree_sitter_language_pack import get_parser


LANGUAGES = {
    ".py": "python",
    ".pyi": "python",
    ".js": "javascript",
    ".mjs": "javascript",
    ".cjs": "javascript",
    ".jsx": "tsx",
    ".ts": "typescript",
    ".tsx": "tsx",
    ".fs": "fsharp",
    ".fsi": "fsharp_signature",
    ".fsx": "fsharp",
    ".cs": "csharp",
    ".sh": "bash",
    ".bash": "bash",
    ".zsh": "bash",
    ".fish": "fish",
    ".ps1": "powershell",
    ".psm1": "powershell",
    ".psd1": "powershell",
    ".html": "html",
    ".htm": "html",
    ".astro": "astro",
    ".css": "css",
    ".scss": "scss",
    ".tf": "hcl",
    ".tfvars": "hcl",
    ".hcl": "hcl",
    ".alloy": "hcl",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".toml": "toml",
    ".json": "json",
    ".jsonc": "json",
    ".jq": "hashconfig",
    ".config": "xml",
    ".sql": "sql",
    ".xml": "xml",
    ".svg": "xml",
    ".plist": "xml",
    ".fsproj": "xml",
    ".csproj": "xml",
    ".props": "xml",
    ".targets": "xml",
    ".slnx": "xml",
    ".lua": "lua",
    ".rs": "rust",
    ".go": "go",
    ".rb": "ruby",
    ".java": "java",
    ".c": "c",
    ".h": "c",
    ".cpp": "cpp",
    ".hpp": "cpp",
    ".kt": "kotlin",
    ".swift": "swift",
    ".ex": "elixir",
    ".exs": "elixir",
    ".vue": "vue",
    ".service": "inilines",
    ".timer": "inilines",
    ".cron": "linehash",
    ".conf": "hashconfig",
    ".ini": "ini",
    ".http": "http",
    ".cmd": "cmd",
    ".bat": "cmd",
}
EXCLUDED_DIRS = {
    ".git",
    "node_modules",
    ".venv",
    "venv",
    "__pycache__",
    ".terraform",
    ".tofu",
    "dist",
    "build",
    "bin",
    "obj",
    "vendor",
    ".gitnexus",
    ".worktrees",
}
GENERATED_NAMES = {
    "bun.lock",
    "bun.lockb",
    "uv.lock",
    "package-lock.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    ".terraform.lock.hcl",
}
IGNORE_NAMES = {
    ".gitignore",
    ".dockerignore",
    ".gitleaksignore",
    ".chezmoiignore",
    ".chezmoiremove",
    ".assetsignore",
    ".prettierignore",
    ".ignore",
    ".gitattributes",
}
TEMPLATE = re.compile(rb"{{-?\s*/\*[\s\S]*?\*/\s*-?}}|{{[\s\S]*?}}")
RULES = r"[A-Za-z0-9_@/.-]+(?:\s*,\s*[A-Za-z0-9_@/.-]+)*"
DIRECTIVES = [
    rf"noqa:\s*{RULES}",
    r"type:\s*ignore\[[a-z0-9-]+(?:\s*,\s*[a-z0-9-]+)*\]",
    r"pyright:\s*ignore\[report[A-Za-z]+(?:\s*,\s*report[A-Za-z]+)*\]",
    rf"pylint:\s*(?:disable|enable)\s*=\s*{RULES}",
    r"shellcheck\s+disable=SC\d+(?:\s*,\s*SC\d+)*",
    r"shellcheck\s+source=/dev/null",
    r"hadolint\s+ignore=DL\d+(?:\s*,\s*(?:DL|SC)\d+)*",
    rf"eslint-(?:disable|enable)(?:-next-line|-line)?\s+{RULES}",
    r"@ts-(?:expect-error|ignore)(?::?\s+[^\r\n]+)?",
    r"biome-ignore\s+lint/[A-Za-z]+/[A-Za-z]+:\s*[^\r\n]+",
]
DIRECTIVE = re.compile("(?:" + "|".join(DIRECTIVES) + ")")
LEGAL = re.compile(
    r"copyright\s*(?:\(c\)\s*)?(?:©\s*)?\d{4}|spdx-license-identifier:\s*\S+"
    r"|@license\b|licensed under (?:the )?(?:mit|apache|bsd|gnu|isc|mozilla)",
    re.I,
)


@dataclass(frozen=True)
class Span:
    start: int
    end: int
    kind: str = "comment"


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    column: int
    kind: str


@lru_cache(maxsize=None)
def parser(language):
    return get_parser(language)


def masked(data):
    return bytes(c if c in (10, 13) else 32 for c in data)


def language_for(path, data):
    p = Path(path)
    name = p.name
    while name.startswith(("private_", "executable_", "modify_")):
        name = name.split("_", 1)[1]
    if name.startswith("dot_"):
        name = "." + name[4:]
    if name.endswith(".in"):
        name = name[:-3]
    if name.endswith(".tmpl"):
        name = name[:-5]
    elif name.endswith(".tftpl"):
        name = name[:-6]
    if name.endswith((".md", ".mdx", ".mdc", ".txt")):
        return None
    if name in IGNORE_NAMES:
        return "linehash" if name == ".gitattributes" else "gitignore"
    if name == ".gitconfig":
        return "hashconfig"
    if name in (
        ".bash_profile",
        ".profile",
        ".zprofile",
        ".zshrc",
        ".zshenv",
        ".bashrc",
        ".npmrc",
    ):
        return "bash" if name != ".npmrc" else "hashconfig"
    if name.lower().startswith(("dockerfile", "containerfile")):
        return "dockerfile"
    if name == "Makefile":
        return "make"
    if name == "Caddyfile":
        return "hashconfig"
    if name.startswith(".env") or name.endswith(".env.example"):
        return "bash"
    if name == "config" and "ssh" in str(p.parent):
        return "hashconfig"
    if name == "authorized_keys":
        return "linehash"
    language = LANGUAGES.get(Path(name).suffix.lower())
    if language:
        return language
    first = data.split(b"\n", 1)[0]
    if first.startswith(b"#!"):
        for marker, language in [
            (b"python", "python"),
            (b"fish", "fish"),
            (b"node", "javascript"),
            (b"pwsh", "powershell"),
            (b"sh", "bash"),
        ]:
            if marker in first:
                return language
        raise ValueError("unsupported executable interpreter")
    return None


def excluded(path, config):
    p = Path(path)
    return (
        bool(set(p.parts) & EXCLUDED_DIRS)
        or p.name in GENERATED_NAMES
        or p.suffix in {".map", ".zip", ".sln"}
        or any(p.match(pattern) for pattern in config.get("generated", []))
    )


def line_spans(data, language):
    offset = 0
    for line in data.splitlines(keepends=True):
        stripped = line.lstrip()
        if language == "gitignore":
            stripped = line
            is_comment = line.startswith(b"#")
        elif language == "cmd":
            is_comment = bool(re.match(rb"(?i)(?:rem(?:\s|$)|::)", stripped))
        elif language == "http":
            is_comment = stripped.startswith((b"#", b"//")) and not stripped.startswith(
                b"###"
            )
        else:
            is_comment = (
                stripped.startswith((b"#", b";"))
                if language == "inilines"
                else stripped.startswith(b"#")
            )
        if is_comment:
            yield Span(
                offset + len(line) - len(stripped), offset + len(line.rstrip(b"\r\n"))
            )
        offset += len(line)


def hash_spans(data):
    quote = None
    i = 0
    while i < len(data):
        c = data[i]
        if c == 92:
            i += 2
            continue
        if quote is not None:
            if c == quote:
                quote = None
        elif c in (34, 39, 96):
            quote = c
        elif c == 35 and (i == 0 or data[i - 1] in b" \t\r\n"):
            end = data.find(b"\n", i)
            end = len(data) if end < 0 else end
            yield Span(i, end)
            i = end
        i += 1


def powershell_spans(data):
    i = 0
    while i < len(data):
        if data[i] == 96:
            i += 2
            continue
        if data[i : i + 2] in (b'@"', b"@'") and re.match(
            rb"@([\"\'])[ \t]*\r?\n", data[i:]
        ):
            end = re.search(
                rb"(?m)^"
                + re.escape(data[i + 1 : i + 2] + b"@")
                + rb"(?=[ \t\r\n;]|$)",
                data[i + 2 :],
            )
            i = i + 2 + end.end() if end else len(data)
            continue
        if data[i : i + 2] == b"${":
            end = data.find(b"}", i + 2)
            i = end + 1 if end >= 0 else len(data)
            continue
        if data[i : i + 3] == b"--%" and (i == 0 or data[i - 1] in b" \t"):
            end = data.find(b"\n", i)
            i = end if end >= 0 else len(data)
            continue
        if data[i] in (34, 39):
            quote = data[i]
            i += 1
            while i < len(data):
                if quote == 34 and data[i] == 96:
                    i += 2
                elif data[i] == quote:
                    if quote == 39 and data[i : i + 2] == b"''":
                        i += 2
                    else:
                        i += 1
                        break
                else:
                    i += 1
            continue
        if data[i : i + 2] == b"<#":
            start = i
            depth = 1
            i += 2
            while i < len(data) and depth:
                if data[i : i + 2] == b"<#":
                    depth += 1
                    i += 2
                elif data[i : i + 2] == b"#>":
                    depth -= 1
                    i += 2
                else:
                    i += 1
            yield Span(start, i)
            continue
        if data[i] == 35:
            end = data.find(b"\n", i)
            end = len(data) if end < 0 else end
            yield Span(i, end)
            i = end
            continue
        i += 1


def comments(data, language):
    if language == "powershell":
        return list(powershell_spans(data))
    if language in {"linehash", "gitignore", "inilines", "cmd", "http", "dockerfile"}:
        return list(line_spans(data, language))
    if language == "hashconfig":
        return list(hash_spans(data))
    tree = parser(language).parse(data)
    result = []
    stack = [tree.root_node]
    while stack:
        node = stack.pop()
        if "comment" in node.type.lower() and node.type != "comment_content":
            result.append(Span(node.start_byte, node.end_byte))
            continue
        if language == "yaml" and node.type == "block_scalar":
            pair = node.parent
            while pair and pair.type in {"block_node", "flow_node"}:
                pair = pair.parent
            key = (
                pair.child_by_field_name("key")
                if pair and pair.type == "block_mapping_pair"
                else None
            )
            if key and data[key.start_byte : key.end_byte].strip(b"\"' ") == b"run":
                start = data.find(b"\n", node.start_byte, node.end_byte) + 1
                script_language = "bash"
                mapping = pair.parent
                if mapping:
                    for sibling in mapping.named_children:
                        sibling_key = sibling.child_by_field_name("key")
                        sibling_value = sibling.child_by_field_name("value")
                        if (
                            sibling_key
                            and sibling_value
                            and data[
                                sibling_key.start_byte : sibling_key.end_byte
                            ].strip()
                            == b"shell"
                        ):
                            if (
                                b"pwsh"
                                in data[
                                    sibling_value.start_byte : sibling_value.end_byte
                                ]
                                or b"powershell"
                                in data[
                                    sibling_value.start_byte : sibling_value.end_byte
                                ]
                            ):
                                script_language = "powershell"
                result.extend(
                    Span(start + s.start, start + s.end)
                    for s in comments(data[start : node.end_byte], script_language)
                )
                continue
        if node.type in {"frontmatter_js_block", "raw_text", "permissible_text"}:
            nested_language = None
            if node.type == "frontmatter_js_block":
                nested_language = "typescript"
            elif node.parent and node.parent.type == "script_element":
                opening = data[node.parent.start_byte : node.start_byte]
                if not re.search(
                    rb"type\s*=\s*[\'\"](?:application/ld\+json|application/json)",
                    opening,
                ):
                    nested_language = (
                        "typescript"
                        if b"typescript" in opening or b'lang="ts"' in opening
                        else "javascript"
                    )
            elif node.parent and node.parent.type == "style_element":
                nested_language = "css"
            elif node.parent and node.parent.type == "html_interpolation":
                nested_language = "tsx"
            if nested_language:
                result.extend(
                    Span(node.start_byte + s.start, node.start_byte + s.end)
                    for s in comments(
                        data[node.start_byte : node.end_byte], nested_language
                    )
                )
                continue
        stack.extend(reversed(node.children))
    return sorted(result, key=lambda span: span.start)


def docstrings(data):
    tree = ast.parse(data.decode("utf-8"))
    offsets = [0]
    for line in data.splitlines(keepends=True):
        offsets.append(offsets[-1] + len(line))
    result = []
    for node in ast.walk(tree):
        if (
            not isinstance(
                node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)
            )
            or not node.body
        ):
            continue
        expr = node.body[0]
        if (
            isinstance(expr, ast.Expr)
            and isinstance(expr.value, ast.Constant)
            and isinstance(expr.value.value, str)
        ):
            result.append(
                Span(
                    offsets[expr.lineno - 1] + expr.col_offset,
                    offsets[expr.end_lineno - 1] + expr.end_col_offset,
                    "docstring",
                )
            )
    return result


def normalized_directive(text):
    text = text.strip()
    for opening, closing in [("<!--", "-->"), ("/*", "*/"), ("(*", "*)"), ("<#", "#>")]:
        if text.startswith(opening) and text.endswith(closing):
            text = text[len(opening) : -len(closing)].strip()
            break
    else:
        text = re.sub(r"^(?:#|//|--|;)+\s*", "", text)
    if re.search(r"\b(?:all|no-comments|no-docstrings)\b", text, re.I):
        return None
    return text if DIRECTIVE.fullmatch(text) else None


def permitted(data, span, language, config):
    text = data[span.start : span.end].decode("utf-8")
    if span.start == 0 and text.startswith("#!") and "\n" not in text:
        return True
    line = data.count(b"\n", 0, span.start)
    if (
        language == "python"
        and line < 2
        and re.fullmatch(r"#\s*(?:-\*-\s*)?coding[:=]\s*[-\w.]+\s*(?:-\*-)?", text)
    ):
        return True
    if hashlib.sha256(data[span.start : span.end]).hexdigest() in config.get(
        "license_notices", []
    ):
        return True
    return span.kind == "comment" and normalized_directive(text) is not None


def violations(path, data, config=None):
    config = config or {}
    if data.startswith(b"\xef\xbb\xbf"):
        data = b"   " + data[3:]
    language = language_for(path, data)
    if language is None:
        return []
    data.decode("utf-8")
    source = data
    template_comments = []
    if str(path).endswith((".tmpl", ".tftpl")) or Path(path).name in {
        ".chezmoiignore",
        ".chezmoiremove",
    }:
        chunks = []
        pos = 0
        for match in TEMPLATE.finditer(data):
            chunks.extend((data[pos : match.start()], masked(match[0])))
            if re.match(rb"{{-?\s*/\*", match[0]):
                template_comments.append(Span(match.start(), match.end()))
            pos = match.end()
        chunks.append(data[pos:])
        source = b"".join(chunks)
    spans = comments(source, language) + template_comments
    if language == "python":
        spans.extend(docstrings(data))
    return [
        span
        for span in sorted(spans, key=lambda span: span.start)
        if not permitted(data, span, language, config)
    ]


def findings(path, data, config=None):
    if Path(path).suffix == ".ipynb":
        notebook = json.loads(data)
        if (
            notebook.get("metadata", {}).get("kernelspec", {}).get("language", "python")
            != "python"
        ):
            raise ValueError("unsupported notebook kernel")
        result = []
        for index, cell in enumerate(notebook.get("cells", [])):
            if cell.get("cell_type") == "code":
                result.extend(
                    findings(
                        f"{path}:cell-{index + 1}.py",
                        "".join(cell.get("source", [])).encode(),
                        config,
                    )
                )
        return result
    return [
        Finding(
            str(path),
            data.count(b"\n", 0, span.start) + 1,
            span.start - (data.rfind(b"\n", 0, span.start) + 1) + 1,
            span.kind,
        )
        for span in violations(path, data, config)
    ]


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def index_files(root):
    entries = git(root, "ls-files", "--stage", "-z").split(b"\0")
    objects = []
    for entry in entries:
        if not entry:
            continue
        metadata, path = entry.split(b"\t", 1)
        mode, oid, stage = metadata.split()
        if stage != b"0":
            raise ValueError("resolve merge conflicts before checking the index")
        if mode in (b"120000", b"160000"):
            continue
        objects.append((path.decode(), oid))
    batch = subprocess.run(
        ["git", "-C", str(root), "cat-file", "--batch"],
        input=b"".join(oid + b"\n" for _, oid in objects),
        stdout=subprocess.PIPE,
        check=True,
    ).stdout
    offset = 0
    for path, _ in objects:
        end = batch.index(b"\n", offset)
        header = batch[offset:end].split()
        size = int(header[-1])
        offset = end + 1
        yield path, batch[offset : offset + size]
        offset += size + 1


def worktree_files(root):
    paths = git(
        root, "ls-files", "--cached", "--others", "--exclude-standard", "-z"
    ).split(b"\0")
    for encoded in sorted(set(paths)):
        if not encoded:
            continue
        path = encoded.decode()
        file = root / path
        if file.is_file() and not file.is_symlink():
            yield path, file.read_bytes()


def main():
    argparser = argparse.ArgumentParser(
        description="Ban source comments and documentation-only Python docstrings."
    )
    argparser.add_argument(
        "--staged",
        action="store_true",
        help="Check the complete index, including partially staged files.",
    )
    argparser.add_argument("--root", type=Path, default=Path.cwd())
    args = argparser.parse_args()
    root = Path(git(args.root, "rev-parse", "--show-toplevel").decode().strip())
    files = dict(index_files(root) if args.staged else worktree_files(root))
    config = json.loads(files.get(".comment-policy/config.json", b"{}"))
    failures = 0
    checked = 0
    for path, data in files.items():
        if excluded(path, config):
            continue
        try:
            problems = findings(path, data, config)
            checked += 1
            for problem in problems:
                print(
                    f"{problem.path}:{problem.line}:{problem.column}: forbidden {problem.kind}",
                    file=sys.stderr,
                )
            failures += len(problems)
        except (ValueError, SyntaxError, UnicodeError, LookupError) as exc:
            print(
                f"{path}: unable to check source ({type(exc).__name__})",
                file=sys.stderr,
            )
            failures += 1
    print(f"No-comments: {checked} files checked; {failures} violations.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
