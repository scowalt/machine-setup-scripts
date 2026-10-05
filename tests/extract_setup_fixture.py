#!/usr/bin/env python3
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

SCRIPTS = ('mac.sh', 'ubuntu.sh', 'pi.sh', 'bazzite.sh', 'wsl.sh')
HEADER = re.compile(r'^([A-Za-z_][A-Za-z_0-9]*)\(\) ([{(])\s*$')
INLINE = re.compile(r'^(print_(?:section|message|success|warning|error|debug))\(\) \{ printf ("(?:[^"\\]|\\.)*") "\$1"; \}$')
LITERAL = re.compile(r"""^(?P<name>[A-Z_][A-Z_0-9]*|_sudo_checked|_has_sudo)=(?:'[^']*'|"[^"$`]*"|[0-9]+)(?:[ \t]+#.*)?[ \t]*$""")
SAFE_CONSTANTS = set('RED GREEN CYAN YELLOW GRAY BOLD NC SETUP_LOG_FILE SETUP_LOG_TEE_PID '
                     'SETUP_LOGGING_ACTIVE DOTFILES_ACCESS_METHOD _sudo_checked _has_sudo '
                     'NPM_CONFIGURATION_COMMAND'.split())
HEREDOC = re.compile(r'''(?<!<)<<(-?)\s*['"]?([A-Za-z_][A-Za-z_0-9]*)''')


def validate_function(block):
    lines = block.splitlines(keepends=True)
    header = HEADER.fullmatch(lines[0].rstrip('\n'))
    if not header:
        raise ValueError('unsupported fixture function boundary')
    closing = '}' if header[2] == '{' else ')'
    if lines[-1].rstrip('\n') != closing:
        raise ValueError('unsupported fixture function boundary')
    alternate_open, alternate_close = ('(', ')') if header[2] == '{' else ('{', '}')
    paired = lines[0].rstrip()[:-1] + alternate_open + '\n' + ''.join(lines[1:-1]) + alternate_close + '\n'
    for candidate in (block, paired):
        parsed = subprocess.run(['/bin/bash', '--noprofile', '--norc', '-n'], input=candidate,
                                text=True, capture_output=True, env={'PATH': '/usr/bin:/bin', 'LANG': 'C'})
        if parsed.returncode:
            raise ValueError('function syntax or outer delimiter validation failed')


def definitions(source):
    output = []
    names = set()
    lines = source.splitlines(keepends=True)
    index = 0
    while index < len(lines):
        line = lines[index].rstrip('\n')
        match = HEADER.fullmatch(line)
        inline = INLINE.fullmatch(line)
        if inline:
            if '$(' in inline[2] or '`' in inline[2]:
                raise ValueError('unsupported fixture print substitution')
            name = inline[1]
            block = f'{name}() {{\n    printf {inline[2]} "$1"\n}}\n'
            validate_function(block)
            output.append(block)
            if name in names:
                raise ValueError('duplicate fixture function')
            names.add(name)
            index += 1
            continue
        if not match:
            if re.match(r'^[A-Za-z_][A-Za-z_0-9]*\(\)', line):
                raise ValueError(f'unsupported fixture function layout at line {index + 1}')
            literal = LITERAL.fullmatch(line)
            if literal and (literal['name'] in SAFE_CONSTANTS or literal['name'].startswith('MACOS_CLT_')
                            or literal['name'] == 'MACOS_DEVELOPER_TOOLS_STATE'):
                output.append(line + '\n')
            index += 1
            continue
        name = match[1]
        closing = '}' if match[2] == '{' else ')'
        if name in names:
            raise ValueError('duplicate fixture function')
        names.add(name)
        block = [lines[index]]
        index += 1
        pending = []
        while index < len(lines):
            line = lines[index]
            block.append(line)
            index += 1
            if pending:
                tabs, delimiter = pending[0]
                candidate = line.rstrip('\n')
                if tabs:
                    candidate = candidate.lstrip('\t')
                if candidate == delimiter:
                    pending.pop(0)
                continue
            if line.startswith(closing) and line.rstrip('\n') != closing:
                raise ValueError('unsupported closing brace or trailing statement')
            if HEADER.fullmatch(line.rstrip('\n')):
                raise ValueError('nested/overlapping top-column function layout')
            if not line.lstrip().startswith('#'):
                pending.extend((bool(m[1]), m[2]) for m in HEREDOC.finditer(line))
            if not pending and line.rstrip('\n') == closing:
                break
        else:
            raise ValueError('unterminated fixture function or heredoc')
        block = ''.join(block)
        validate_function(block)
        output.append(block)
    if not {'main', 'run_setup_tasks', 'setup_load_environment'} <= names:
        raise ValueError('required caller definitions missing')
    output.append('SETUP_ORIGINAL_PATH="${PATH}"\nSETUP_ORIGINAL_CLAUDE_COMMAND=""\n')
    result = '\n'.join(output)
    parsed = subprocess.run(['/bin/bash', '--noprofile', '--norc', '-n'], input=result,
                            text=True, capture_output=True, env={'PATH': '/usr/bin:/bin', 'LANG': 'C'})
    if parsed.returncode:
        raise ValueError('extracted fixture failed syntax validation')
    return result


def materialize(root):
    contents = {name: definitions((root / name).read_text()) for name in SCRIPTS}
    destination = Path(tempfile.mkdtemp(prefix='setup-definitions-only-'))
    destination.chmod(0o700)
    for name, content in contents.items():
        target = destination / name
        target.write_text(content)
        target.chmod(0o600)
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Materialize definitions-only Bash fixtures; never copy production entry calls.\n\nThis is a bounded extractor for this repo's function layout, not a shell parser.\nUnexpected layouts or unterminated here-documents fail before any file is emitted.\nEach candidate is independently parsed twice: normally and with ONLY its outer\nopening/closing delimiters exchanged between braces and subshell parentheses.\nThe second parse rejects an earlier real function close in either supported form.\nThis is bounded delimiter validation with Bash's parser, not a general Bash AST.\n")
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    print(materialize(args.root.resolve()))
