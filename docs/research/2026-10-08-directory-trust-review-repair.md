# Directory trust review repair — #208 / #214

Repairs the single spec-review P2 against integration `cae1920f95657ed8298a99b34da89d5fd0bd2110`: failed OpenCode staging skipped directory revalidation when neither promotion nor quarantine had occurred, allowing cleanup through substituted ancestry. Standards review reported no findings. Prior [slice](2026-10-07-directory-trust-214.md) and [integration](2026-10-07-directory-trust-integration.md) reports remain historical, unchanged.

## Repair and regression

`lib/opencode-cli.cjs::installChecked` now always revalidates captured account directories on the incomplete-transaction recovery path, before rollback or stage/lock cleanup. Uncertainty retains artifacts and wraps the **original** controlled failure in `RecoveryError`. This removes one conditional; file/root/private rules, recognized paths, Homebrew recovery, Windows ACL policy and result vocabulary are unchanged. Windows still has no Unix directory-snapshot map.

Eight regressions exercise the existing real `install`/`probe` seam with inert artifact/child-process boundaries. During the staged probe they actually rename `.local` or `.local/bin`, substitute a real directory or symlink, and seed identically named replacement stage/lock paths plus sentinels. No fabricated stat identity stands in for replacement. Assertions compare descendant bytes and dev/inode/UID/GID/mode/link-count/size/mtime/ctime in both replacement and displaced trees; original private stage/lock modes remain 0700, the displaced ordinary boundary remains 02775, and the prior command survives without promotion or receipt publication. Both successful-probe directory-change failures and independently failing probes retain their exact controlled reasons (`changed-copy` and `version-probe`) under `recovery-required`, never raw exception text.

All six embeddings were regenerated. Banners: macOS **292**, Ubuntu **323**, WSL **249**, Pi **266**, Bazzite **170**, Windows **188**. No caller/adapter, loader, runner, dispatcher or kernel-filter implementation changed.

## Exact validation

Read full #208/#214, ADRs, OpenCode sources/fixtures, fixture audit/incident and TDD guidance before execution. All behavioral runs serialized on the same global fixture lock, with mandatory unchanged kernel/FD containment, private roots/stdio and optional integrations disabled.

```sh
flock /tmp/setup-208-coordination/fixtures.lock env -i PATH=/usr/bin:/bin \
 /usr/bin/python3 -I tests/run-fixture-matrix.py \
 --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
 --pwsh /opt/microsoft/powershell/7/pwsh \
 --tool-path /usr/bin:/bin:/tmp/setup-208-coordination/tools \
 --timeout 900 tests/opencode-cli-contract.sh
```

| Run | Private artifact root | Result |
| --- | --- | --- |
| Untouched integration baseline; same prefix without `--timeout`, suffix `tests/setup-default-contract.sh tests/test_fixture_containment.py` | `/tmp/setup-fixture-matrix-8xr3lyyt` | 2/2 pass: defaults/environment and actual-source extraction/containment. |
| Red; new tests, unchanged production | `/tmp/setup-fixture-matrix-q4shtejz` | Exit 1: all **8** new cases fail because cleanup deleted replacement locks/stages/sentinels. Node: 418 pass, 8 fail, 1 optional skip. Contract stops before callers. |
| Green; identical tests, one-line fix and embeddings | `/tmp/setup-fixture-matrix-rk51d6b4` | Exit 0: Node **426 pass, 0 fail, 1 optional skip**; five captured-Mac methods and **13 Bash/PowerShell caller methods** pass. |
| Final complete dispatcher below, implementation commit `f853efc3cfddc5b335a5cba2ecb60d0660e2a4bd` | `/tmp/setup-fixture-matrix-zlztbh6m` | Exit 0: **46/46 entries pass**, 1,898.7 suite-seconds, no timeout. Same focused counts; 708 unittest method executions including 16 explicit skips. |

```sh
flock /tmp/setup-208-coordination/fixtures.lock env -i PATH=/usr/bin:/bin \
 /usr/bin/python3 -I tools/run-pre-push-contracts.py \
 --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
 --pwsh /opt/microsoft/powershell/7/pwsh \
 --mise /home/scowalt/.local/bin/mise \
 --chezmoi /home/scowalt/.local/bin/chezmoi \
 --bun /home/scowalt/.bun/bin/bun
```

Integration merge returned `Already up to date` before and after the aggregate; ancestry of `cae1920` is verified. Aggregate implementation tree: `0a2b4eaade42af331e8d9ba58a8d2deda44bf43f`. All **134** executable/fixture/tool/lint-control source hashes were captured before execution and compared afterward without drift. Subsequent changes only add this evidence and its [source/result manifest](2026-10-08-directory-trust-review-repair-source.json), which includes every suite status/duration and log digest. The manifest also exists in the aggregate artifact root.

| SHA-256 evidence | Digest |
| --- | --- |
| Red canonical core | `9acdba814aefd321ea4ec2d6c816891186f786714e8f86d8c82cba4a9b99f232` |
| Green/final canonical core | `023679fbf760e71d26954af2ec50b9b0ef130b92400872f059ade9e0505d9e84` |
| Identical red/green/final test source | `6bdf800afff759f17d6ed30d811a9e7f30bf37137d7fb16751229d81e10f332a` |
| Final `results.json` | `10411cae9320089be29157827f133f7e2dba984c02276429a2236fb1a4d20a25` |
| Final 134-source map (sorted compact JSON, no newline) | `3cbcc19e8612aa7542b4a62062b14680c90a9f0a14fba8adadc2831c663830d5` |
| Committed source/result manifest | `5807d0d6ef0869de6a0cb6d4c7235dc8263eadb87c5b0c411317d85c86fed161` |

Static checks pass: native ShellCheck and Bash syntax on all five modified Bash entries, Node syntax on core/tests, all four embedding checks, whitespace, cached Markdownlint, cached Python 3.14 comment-policy and native Gitleaks. PowerShell AST/caller validation ran contained. Static log: `/tmp/setup-208-coordination/review-repair-static.log` (copied into the aggregate root). Commits use a command-local empty hooks path; no resolver-backed hooks or tool installations were invoked. AI attribution identifies the executing `gpt-6-astra` / `openai-codex` model.

## Omissions and boundaries

No implementation/aggregate blocker remains. Explicit omissions match the prior aggregate: installed CLI/dotfiles managed-skill integrations (three, repeated in weekly), native Bash 3.2, external Paseo/AskClaude/runtime dotfiles, installed Go catalog/lock (two), installed Pi registry/dotfiles (two), native Pi Windows ACL/handle (two), optional OpenCode cmd-shim, and separate Backlog native Windows handle/ACL coverage. Counts include repeated suites, not unique tests.

No live setup, real application/skill/extension/BB/plugin execution, native installer, provider request, service/process inventory, credentials, permission repair or fleet operation was used. No source-loading or fixture-containment boundary changed; filter/runner/extractor hashes remain identical to `75fc596` and are in the manifest. No new containment refusal or unexpected real effect was observed; this was not a syscall-wide effects audit. Linux-hosted platform simulations are not native macOS/Windows/ARM/WSL/Bazzite or live recovery/readiness evidence. Historical incident receipt/retention/telemetry uncertainty remains unchanged. No agents spawned, pushes or issue closures; publication and rollout remain with the parent/user.
