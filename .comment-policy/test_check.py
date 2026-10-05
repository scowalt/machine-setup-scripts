import hashlib
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import check


class CommentPolicyTests(unittest.TestCase):
    def test_each_ecosystem_rejects_comments_but_preserves_strings(self):
        cases = [
            ("a.py", 'value = "# data"\n# note\n'),
            ("a.ts", 'const value = "// data";\n// note\n'),
            ("a.tsx", 'const value = <div>{"/* data */"}</div>;\n/* note */\n'),
            ("a.fs", 'let value = "// data"\n// note\n'),
            ("a.cs", 'class C { string value = "// data"; /* note */ }'),
            ("a.sh", 'value="# data"\n# note\n'),
            ("a.fish", 'set value "# data"\n# note\n'),
            ("a.ps1", '$value = "# data"\n<# note #>\n'),
            ("a.css", 'a::after {content: "/* data */";}\n/* note */'),
            ("a.tf", 'value = "# data"\n# note\n'),
            ("a.alloy", 'value = "// data"\n// note\n'),
            ("a.yml", 'value: "# data"\n# note\n'),
            ("a.toml", 'value = "# data"\n# note\n'),
            ("a.jsonc", '{"value": "// data"}\n// note\n'),
            ("a.sql", "SELECT '-- data'; -- note\n"),
            ("a.xml", '<a value="data"/><!-- note -->'),
            ("a.html", '<a data-value="// data"/><!-- note -->'),
            ("Dockerfile", 'FROM alpine\nENV VALUE="# data"\n# note\n'),
            ("Caddyfile", 'respond "# data"\n# note\n'),
            ("a.service", '[Service]\nEnvironment="VALUE=# data"\n# note\n'),
            ("a.cmd", 'echo "REM data"\nREM note\n'),
            ("Makefile", 'target:\n\techo "# data"\n# note\n'),
            ("a.lua", 'local value = "-- data"\n-- note\n'),
            ("config.jq", '"# data" | .\n# note\n'),
            ("NuGet.Config", '<configuration value="data"/><!-- note -->'),
            ("fixture.fsx.in", 'let value = "// data"\n// note\n'),
        ]
        for path, source in cases:
            with self.subTest(path=path):
                spans = check.violations(path, source.encode())
                self.assertEqual(len(spans), 1)
                self.assertIn(
                    "note", source.encode()[spans[0].start : spans[0].end].decode()
                )

    def test_python_docstrings_are_rejected_but_regular_strings_are_not(self):
        source = '"""module"""\nclass C:\n    """class"""\n    def f(self):\n        ("function " "documentation")\n        return "# data"\nvalue = """ordinary string"""\n'
        self.assertEqual(
            [span.kind for span in check.violations("a.py", source.encode())],
            ["docstring"] * 3,
        )

    def test_embedded_astro_html_and_jsx_comments_are_checked(self):
        cases = [
            (
                "a.astro",
                '---\n// note\nconst x="// data";\n---\n<div>{/* note */ x}</div><script>// note\nconst x="// data";</script><style>/* note */ a {color:red}</style><!-- note -->',
            ),
            (
                "a.html",
                '<script>const x="// data"; // note\n</script><style>/* note */ a {color:red}</style><!-- note -->',
            ),
            ("a.tsx", 'const x = <div>{/* note */ "// data"}</div>;'),
        ]
        for path, source in cases:
            with self.subTest(path=path):
                expected = (
                    5 if path.endswith(".astro") else 3 if path.endswith(".html") else 1
                )
                self.assertEqual(len(check.violations(path, source.encode())), expected)

    def test_yaml_run_scripts_are_code_but_other_scalar_strings_are_data(self):
        source = b'description: |\n  # ordinary data\nsteps:\n  - run: |\n      echo "# ordinary data"\n      # note\n  - shell: pwsh\n    run: |\n      $a = "# ordinary data"\n      <# note #>\n'
        self.assertEqual(len(check.violations("workflow.yml", source)), 2)

    def test_narrow_exceptions(self):
        allowed = [
            (
                "a.py",
                "#!/usr/bin/env python3\n# -*- coding: utf-8 -*-\nx = 1 # noqa: F401, E402\n",
            ),
            ("a.py", "x = 1 # type: ignore[arg-type]\n"),
            ("a.py", "x = 1 # pyright: ignore[reportArgumentType]\n"),
            (
                "a.ts",
                "// eslint-disable-next-line @typescript-eslint/no-explicit-any\nlet x: any;",
            ),
            (
                "a.ts",
                '// @ts-expect-error: required type-checker rationale\nconst x: number = "bad";',
            ),
            ("a.sh", "#!/bin/sh\n# shellcheck disable=SC2086\necho $x\n"),
        ]
        for path, source in allowed:
            with self.subTest(source=source):
                self.assertEqual(check.violations(path, source.encode()), [])
        banned = [
            "# noqa",
            "# noqa: F401 arbitrary prose",
            "# type: ignore",
            "# pylint: disable=all",
        ]
        for source in banned:
            self.assertEqual(
                len(check.violations("a.py", (source + "\nx = 1\n").encode())), 1
            )
        for source in [
            "// eslint-disable",
            "// eslint-disable no-comments",
            "// eslint-disable-next-line no-comments",
            "// eslint-disable foo -- prose",
        ]:
            self.assertEqual(len(check.violations("a.ts", source.encode())), 1)

    def test_legal_notice_exemption_requires_exact_retained_content(self):
        notice = b"# Copyright 2026 Example"
        config = {"license_notices": [hashlib.sha256(notice).hexdigest()]}
        self.assertEqual(check.violations("a.py", notice + b"\nx = 1\n", config), [])
        self.assertEqual(
            len(
                check.violations(
                    "a.py", notice + b" and arbitrary prose\nx = 1\n", config
                )
            ),
            1,
        )
        self.assertEqual(
            len(
                check.violations("a.py", b"# @license arbitrary prose\nx = 1\n", config)
            ),
            1,
        )

    def test_only_initial_shebang_and_initial_encoding_are_allowed(self):
        self.assertEqual(
            len(check.violations("a.py", b"x = 1\n#!/usr/bin/python\n")), 1
        )
        self.assertEqual(
            len(check.violations("a.py", b"x = 1\nx = 2\n# coding: utf-8\n")), 1
        )

    def test_powershell_here_strings_and_escape_sequences_are_data(self):
        source = b'$a = @"\n# data\n<# data #>\n`"quoted`"\n"@\n$b = @\'\n# data\n\'@\n$c = \'# data doubled\'\'quote\'\n$d = "`"# data`""\n# note\n'
        self.assertEqual(len(check.violations("a.ps1", source)), 1)
        self.assertEqual(check.violations("a.ps1", b"cmd --% echo # literal\n"), [])
        self.assertEqual(
            check.violations(
                ".gitignore", b"  # literal filename\n\\# escaped filename\n"
            ),
            [],
        )

    def test_templates_use_host_language_and_reject_go_comments(self):
        self.assertEqual(
            len(
                check.violations(
                    "dot_config/config.toml.tmpl",
                    b'{{ if .condition }}\nx = "# data"\n# note\n{{ end }}\n',
                )
            ),
            1,
        )
        self.assertEqual(
            len(
                check.violations(
                    "config.json.tmpl", b'{"value": "{{ .value }}"} {{/* note */}}'
                )
            ),
            1,
        )
        self.assertEqual(
            check.violations("AGENTS.md.tmpl", b"# Documentation\n{{/* prose */}}"), []
        )

    def test_fsharp_nested_comments_and_unicode_offsets(self):
        source = 'let text = "✓ (* data *)"\n(* outer (* nested *) note *)\n'.encode()
        spans = check.violations("a.fs", source)
        self.assertEqual(len(spans), 1)
        self.assertEqual(
            source[spans[0].start : spans[0].end], b"(* outer (* nested *) note *)"
        )

    def test_notebook_cells_are_code_but_markdown_and_outputs_are_data(self):
        source = b'{"cells":[{"cell_type":"code","source":["x = 1 # note\\n"],"outputs":["# output"]},{"cell_type":"markdown","source":["# heading"]}],"metadata":{}}'
        self.assertEqual(len(check.findings("a.ipynb", source)), 1)

    def test_generated_files_and_markdown_are_excluded(self):
        for path in [
            "dist/a.js",
            "src/vendor/a.js",
            "obj/a.cs",
            "uv.lock",
            "package-lock.json",
            "function.zip",
        ]:
            self.assertTrue(check.excluded(path, {}))
        self.assertFalse(check.excluded("src/clock.py", {}))
        self.assertEqual(check.findings("README.md", b"# Heading\n<!-- prose -->"), [])
        self.assertTrue(
            check.excluded("wwwroot/bundle.js", {"generated": ["wwwroot/bundle.js"]})
        )

    def test_staged_check_reads_index_not_worktree(self):
        env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith("GIT_")
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.run(
                    ["git", "-C", directory, "-c", "core.hooksPath=/dev/null", *args],
                    env=env,
                    capture_output=True,
                    check=True,
                )

            git("init")
            file = root / "space in name.py"
            file.write_text("x = 1 # staged comment\n")
            git("add", "--", file.name)
            file.write_text("x = 1\n")
            indexed = dict(check.index_files(root))
            self.assertEqual(len(check.findings(file.name, indexed[file.name])), 1)
            self.assertEqual(check.findings(file.name, file.read_bytes()), [])
            file.write_text("x = 1\n")
            git("add", "--", file.name)
            file.write_text("x = 1 # unstaged comment\n")
            indexed = dict(check.index_files(root))
            self.assertEqual(check.findings(file.name, indexed[file.name]), [])


if __name__ == "__main__":
    unittest.main()
