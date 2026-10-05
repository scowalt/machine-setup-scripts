# Comment-free source

Write intent in names, types, explicit runtime metadata, and tests. Keep prose in
Markdown. Hand-maintained source, tests, scripts, configuration, infrastructure,
markup, styles, templates, and Python notebook code cells are comment-free.
Documentation-only Python docstrings, JSDoc, and XML documentation comments are
also banned. Runtime descriptions belong in explicit metadata, such as Click
`help=` or FastAPI `description=`.

## Run and install

Install [uv](https://docs.astral.sh/uv/getting-started/installation/) and
[Lefthook](https://lefthook.dev/installation/). The checker uses an isolated,
pinned parser environment; application dependencies and runtimes are unchanged.

```sh
lefthook install pre-commit
uv run --no-project --python 3.14 --with-requirements .comment-policy/requirements.txt python .comment-policy/check.py
uv run --no-project --python 3.14 --with-requirements .comment-policy/requirements.txt python -m unittest discover -s .comment-policy -p 'test_*.py'
```

The pre-commit hook passes `--staged` and reads the **complete Git index**, not the
working copy. Partially staged files cannot conceal a staged comment. Stage the
initial cleanup together with the policy before committing. The manual command
checks tracked and non-ignored new files. The GitHub Actions workflow checks the
committed checkout and runs the checker regression suite on pushes and PRs.
Hooks can be bypassed, but the CI workflow still reports violations. Making this
workflow a required branch-protection check is an owner-controlled GitHub setting.

## Narrow exceptions

- Initial shebangs and Python encoding declarations on the first two lines.
- Valid, rule-specific lint/type-check directives. Blanket disables, appended
  prose, and suppression of the comment ban itself are rejected. TypeScript and
  Biome directives may carry the rationale their lint rules require.
- Existing legally required notices identified by exact SHA-256 hashes in
  `config.json`. Appending prose changes the hash and fails the check.

Ordinary string data and Markdown, including fenced examples, are outside the
ban. Embedded Astro/HTML script and style blocks and YAML `run` blocks are checked
as code. HTTP request separators are protocol syntax rather than comments.
Generated outputs, dependency directories, lockfiles, vendored code, Git
metadata, and additional worktrees are excluded. Repository-specific generated
paths are listed explicitly in `config.json`; do not use this to exclude authored
source. Historical SQL migrations have no exemption.

## Maintenance

Tree-sitter grammars identify comments without matching comment-like characters
inside strings. Python ASTs identify docstrings; PowerShell, simple configuration,
and batch formats use format-aware lexers. New source formats need an adapter and
positive/negative fixtures before adoption. Unsupported executable interpreters,
source decoding errors, and Python AST failures fail closed. Tree-sitter recovery
nodes are tolerated because the pinned grammars lag some valid language syntax;
this checker is not a syntax validator. Keep native compiler and linter checks.

The checker and its regression suite are versioned copies of Mission Control's
`.comment-policy/` implementation so every checkout and CI job is self-contained,
including private repositories. Keep these copies synchronized when fixing or
extending the shared checker. Review exception changes as policy changes, not
ordinary lint suppressions. This repository's existing security, formatting,
type-checking, and test hooks remain in place.
