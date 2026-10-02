---
id: TASK-68
title: Contain the pre-push contract suite through the audited fixture runner
status: Done
assignee:
  - '@pi'
created_date: '2026-10-02 14:19'
updated_date: '2026-10-02 15:19'
labels: []
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The normal pre-push contract hook dispatches fixtures directly despite mandatory containment. User approved the prerequisite hook repair; glossary migration remains preserved and publication awaits parent review.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The normal hook runs every shell contract sequentially through the existing sanitized kernel-contained runner, without optional live probes.
- [x] #2 Inert regression tests prove hook wiring, sanitized arguments/environment, complete selection, and tool/containment/test failure propagation; missing tools fail closed.
- [x] #3 Contained affected and full hook coverage and static checks are reported with baseline failures and optional/native gaps explicit; existing lint/secret hooks and production setup remain unchanged.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Capture a static red test for the unsafe hook without dispatching fixtures.
2. Add a sanitized explicit-tool dispatcher around the unchanged runner and inert seam regressions.
3. Run containment/default and targeted tests, then full shell-contract selection through the actual dispatcher; inspect scope/lint and report for parent review.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
User explicitly approved implementation of the hook prerequisite. Audit/incident and current rollback evidence reviewed. No uncontained fixture was executed; the existing direct hook loop is a source-proven safety mismatch.

Red: env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh --tool-path /usr/bin:/bin tests/test_pre_push_contracts.py failed its sole static assertion on the exact direct shell loop. Artifacts: /tmp/setup-fixture-matrix-hvvxij6_. The old loop was never executed.
Green targeted: same runner/tool arguments with tests/test_fixture_containment.py tests/setup-default-contract.sh tests/test_pre_push_contracts.py passed 3/3 at /tmp/setup-fixture-matrix-j_h1lxy_.
Implemented one hook command replacement plus tools/run-pre-push-contracts.py and seven inert regression methods. Tests execute the actual hook command in a synthetic repository with a recording runner and inert ELF files. Checks cover full shell inventory (including a future contract), stripped credentials/Git/agent/optional-probe environment, private allowlisted tool links, missing/relative/shim tools, unsupported platforms, launch failures and simulated runner statuses 1/2/125. Actual kernel refusal was not observed.
Full validation extracted the exact contract-tests run command from lefthook.yml and executed it with /bin/sh, supplying only PATH=/usr/bin:/bin and five explicit selections: SETUP_TEST_NODE=/home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node, PWSH_BIN=/tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh, SETUP_TEST_MISE=/home/scowalt/.local/bin/mise, SETUP_TEST_CHEZMOI=/home/scowalt/.local/bin/chezmoi, SETUP_TEST_BUN=/home/scowalt/.bun/bin/bun. Its committed env -i command entered the unchanged runner. Result: 42/42 entries pass (37 shell + 5 direct Python) at /tmp/setup-fixture-matrix-bjr37h2x; kernel self-test passed, sequential execution, no observed unexpected effects. This validates the full contract command, not the other Lefthook commands.
ShellCheck on all five production Bash scripts and the two glossary assertion scripts, Bash/Python syntax and both diff checks pass. Secret scanning/ShellCheck/Markdownlint hook definitions, runner, kernel filter and production code remain unchanged. Trusted Markdownlint is unavailable; no package download, mutable-cache execution or lint bypass attempted. Optional installed-code/cross-repository/native tests remain skipped (16 reported unittest skips, one Node skip, separate native Windows handle/ACL omission); native rollout and historical incident uncertainty unchanged.
Glossary migration preserved; no commits/pushes/PRs. Leaving In Progress for parent safety review and explicit publication resumption.

Publication retry: fetched origin/main edc524a and safely fast-forwarded this worktree using a temporary stash, restoring the reviewed migration/repair without conflict. Upstream BB diagnostic changes are preserved.
STOPPED during lint-tool preparation before any commit or push. Created private /tmp/glossary-hook-lint-fq4dh306 and fetched official markdownlint-cli@0.45.0 metadata. npm refused because /dev/null was supplied as both userconfig and globalconfig. A command-sequencing mistake allowed the subsequent bunx --no-install version probe to run despite install/integrity setup failure. Even with private HOME and BUN_INSTALL_CACHE_DIR, it printed 0.49.1; read-only inspection found matching 0.49.1 in /tmp/bunx-1000-markdownlint-cli@latest. This is consistent with executing the forbidden shared bunx cache, not the intended pinned verified tool. No verified lint run or clean safety claim is made. No --fix invocation or Git hook ran, and repository status still contains only the reviewed changes/new task. Arbitrary effects of that untrusted execution were not traced.
Parent review required before retry. Proposed narrow correction: distinct private npm config files, fail-fast command sequencing, private TMPDIR for bunx resolution, and verify the pinned package/lock integrity and exact dispatch target before any execution. Do not modify or delete the shared cache. No commits/pushes/PRs or provisioning performed.

Parent approved the safety repair and resumed publication. A single new private npm installation succeeded at /tmp/glossary-hook-trusted-co1kb45k with distinct configs, lifecycle scripts disabled and private HOME/cache/TMPDIR/TMP/TEMP. Before any tool execution, all 82 package tarballs were matched to official registry version/integrity metadata and installed file bytes; the sole npm bin-links transformation was the documented CRLF shebang normalization in run-con/cli.js. Static verifier corrections for that normalization and varying archive root names did not execute package code.
Inspected Bun 1.3.11 primary resolver source: unversioned initial binary names resolve from configured PATH before temp cache fallback. Checked all enclosing node_modules/.bin and cwd candidates absent; private links select the verified markdownlint-cli JS and /usr/bin/shellcheck. A hash/path guard rejects missing preparation before subprocess execution. Exact unchanged bunx command probes then returned Markdownlint CLI 0.45.0 and ShellCheck 0.9.0; native Gitleaks is 8.30.1. No bunx cache was created in the new private temp root. Earlier untrusted shared-cache probe remains separately recorded and untraced. Actual commit/push hooks have not yet run.

Actual Git pre-commit passed with Gitleaks 8.30.1, verified private Markdownlint CLI 0.45.0 and system ShellCheck 0.9.0; commit 2d13c25 contains the reviewed migration/repair. Formatter added only one blank line before a list in each of existing TASK-57 and TASK-64, both already in migration scope. Complete main-to-branch diff and commit list reviewed; all six production entry points, runner/filter and glossary bytes remain preserved relative to integrated origin/main edc524a.
Actual git push pre-push hook passed all three commands: 42/42 contained contract entries at /tmp/setup-fixture-matrix-aikscm01 (37 shell + 5 direct suites), markdownlint-all and shellcheck-all. This includes the new upstream BB service preflight tests, reviewed for definitions-only imports, inert mocks, private roots and inherited socket denial before execution. No hook bypass or shared-cache resolution used for these successful runs. Topic branch pushed normally. No observed containment refusal/unexpected fixture effect; optional/native gaps and the earlier untraced version-probe incident remain unchanged.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Repaired normal pre-push contract dispatch to use the unchanged sanitized sequential kernel-contained runner, preserving every shell contract and adding direct hook/containment/CLT/Homebrew/managed-skill coverage. Explicit existing native tools are required; missing tools, shims and unsupported platforms fail closed. Credentials, Git overrides and optional live-probe inputs do not reach fixtures.
Seven inert hook-dispatch regressions pass after a static red test caught the original unsafe loop without executing it. Actual Git pre-commit and pre-push hooks now pass, including all 42 contained entries, Gitleaks, Markdownlint and ShellCheck. The full source diff preserves production setup and glossary bytes. Parent safety review approved the repair.
Private pinned lint preparation verified registry metadata, integrity and installed bytes before successful hooks. The earlier accidental shared-cache version probe remains explicitly recorded as untraced; later success does not prove it harmless. Native-platform rollout and optional integrations remain unverified. Implementation complete; PR publication/merge proceeds under separate authorization.
<!-- SECTION:FINAL_SUMMARY:END -->
