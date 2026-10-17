# CI

## Native Linux routing

The workflow selects `ci_os: linux`, matching the supported Woodpecker 3.19
agent setting `WOODPECKER_AGENT_LABELS=ci_os=linux`. Before merging this change,
the parent must configure and read back that label and actual Linux ARM64
platform on the current agent, then verify the label and Linux AMD64 platform
on its replacement. Include no other OS or unsupported CPU; retain native platform
reporting. This routing label is not a security boundary or hardware attestation.
The original image index supports both targets, without a matrix or emulation.
ARM64 rollout guidance below is historical, not native AMD64 proof. Commands,
pins and status layout stay unchanged; actual AMD64 acceptance is separate.

## Authored contract

[.woodpecker.yaml](.woodpecker.yaml) ports the sole authored GitHub Actions job,
`no-comments`, from [.github/workflows/no-comments.yml](.github/workflows/no-comments.yml).
Both run these commands, in order, failing on a nonzero result:

```sh
uv run --no-project --python 3.14 --with-requirements .comment-policy/requirements.txt python .comment-policy/check.py
uv run --no-project --python 3.14 --with-requirements .comment-policy/requirements.txt python -m unittest discover -s .comment-policy -p 'test_*.py'
```

The original unfiltered `push` includes tags; Woodpecker represents this as
`push` and `tag`, alongside `pull_request`. There are no branch or path filters.
Fork PRs remain eligible but require native approval before execution.
No schedule, deployment, publishing, application build or native setup job is
authored. No deployment-controller configuration is tracked here; the script
hosting described in README is not a new CI deployment authorization.

The image pins uv 0.11.32 and Python 3.14 on Debian trixie by digest
`sha256:adafbab0c780d8bd995039e9dfd800f95a057867d283deee7d5eb1b3126551b2`.
The `ci_os: linux` label selects the native Linux ARM64/AMD64 pool, not emulation.
[Requirements](.comment-policy/requirements.txt) remain tree-sitter 0.25.2,
tree-sitter-language-pack 0.13.0, tree-sitter-c-sharp 0.23.5,
tree-sitter-embedded-template 0.25.0 and tree-sitter-yaml 0.7.2.
Git must be available for real tracked-file/index enumeration and the original
13 regression tests, including their disposable Git repositories.

The native default clone provides the committed checkout and Git index. The
original checkout action requests no full history or all-ref scan; neither
command needs these. The checker enumerates tracked and non-ignored new files;
its `--staged` mode checks the complete index, not just a diff. Preserve the
parser implementation, tests, exclusions and generated-path lists. Actions'
setup-uv cache is an optimization, not a required input; no shared host cache or
custom clone is introduced. Original Actions and its action SHA pins stay intact
for comparison and rollback.

## Local boundaries

Run the same two commands above for policy validation; stage only intended files
and run the first command with `--staged` to check the complete proposed snapshot.
Install the existing hooks with `lefthook install` and make an ordinary hooked
commit. Keep [lefthook.yml](lefthook.yml) unchanged: pre-commit retains staged
Gitleaks, ShellCheck, Markdownlint and policy checks; pre-push retains all-script
lint and the contained contract dispatcher. `.mise.toml` pins local Gitleaks
8.30.1; use process-local `mise exec`, not a global version change.
These local suites are not additional authored hosted jobs.

Never validate this port by running or sourcing setup scripts, applying dotfiles,
updating managed tools, or contacting production services. Behavioral fixtures
remain subject to the [execution audit](docs/research/2026-09-29-fixture-execution-audit.md)
and linked incident: sanitized native runner, explicit existing tools, mandatory
kernel filter/self-test, private I/O and roots, sequential suites, no fallback.
The policy commands parse source and test only their own temporary Git fixtures;
they do not establish native macOS/Windows or fleet readiness.

## Parent-owned delivery and cutover

Source preparation is not activation or acceptance. The parent serializes live
operations on the existing single CAX11 agent (4 GiB host, capacity 1, 2 GiB job
limit), without new capacity, spend, credentials or trust.

1. Obtain separate integration review of the pinned source commit/tree and verify
   every original path, mode and blob, especially the Actions workflow, is
   unchanged. Keep GitHub Actions enabled. Snapshot existing native settings,
   Actions permissions, required checks, protections and rulesets.
2. Activate using the supported native interface and read back the intended
   pipeline path, PR handling and push/tag hooks. Set and read back repository
   timeout **10 minutes**, matching the original job; there is no YAML timeout.
   Require fork approval, `approval_allowed_users=[]`, and all trusted network,
   volumes and security flags false. Keep reports private, deployments disabled
   and job secrets absent. No operator/admin/publishing/production credentials,
   authentication bootstrap, privileged containers, sockets or host mounts in
   jobs; use the standard native clone boundary only.
3. Deliver ONE ordinary reviewed PR. Record its exact head SHA/tree and actual
   native PR clone/job logs: both original commands, 13 tests, policy file count
   with zero violations and ARM64 agent identity. Require matching successful
   exact-SHA GitHub feedback. Configured tag/fork
   eligibility is not evidence of executing those events. MC PR29/#26 already
   supplied controlled RED-to-GREEN and same-PR post-disable proof once; do not
   repeat failures, marker commits, artificial PRs or tag/fork events here.
4. Merge normally with `gh pr merge --match-head-commit <reviewed-head>` and the
   repository's normal merge method. Record the ACTUAL resulting default-main
   SHA, tree and ordered parents, confirm the reviewed content/original workflow,
   and require native **push** clone/job success plus matching exact-SHA GitHub
   success for that resulting main revision.
5. Only after both PR and resulting-main proof, replace corresponding Actions
   requirements with the observed native context, preserving unrelated checks,
   protections and rules. Empty requirements/protections/rules mean a replacement
   no-op, not invented rules or unrelated removal. Then write only Actions
   `enabled=false`; retain all original workflows and other settings.
6. Obtain separate fresh GET-only acceptance of native/GitHub evidence, current
   main identity, safety settings, requirements and disabled Actions. Record a
   bounded observation of Actions runs created since disable. Generate no fresh
   post-disable revision/event; absence is not an infinite-future guarantee.

If commands, inputs, platform, credentials or capacity cannot be preserved, stop,
record the concrete blocker and leave Actions enabled rather than substitute a
partial pipeline. For rollback, the parent re-enables Actions with its saved
permissions, verifies the unchanged workflow at the intended revision and restores
only the corresponding saved requirements after observing its result. Disable
native execution if needed; do not change deployment controllers or source.
