# Upstream compatibility implementation evidence

Status: implementation and publication validation complete, except trusted Markdownlint unavailable. The user requested publication to remote main; integrated-source validation is recorded below. TASK-63, TASK-61 and TASK-62 remain In Progress for the lint validation gap; no native rollout is claimed.

## Scope and review

Implemented the [user-approved plan](../plans/2026-10-01-001-fix-setup-upstream-compatibility.md) in the existing worktree based on `4bb7feb`. No commits, branch changes, live setup, application/skill execution, model requests, external dotfiles changes or optional installed-code integrations were performed.

- **TASK-63** (originally branch-local TASK-60): all six Go helpers accept the legacy Muse key or exact `chat:` key. Semantic-ID uniqueness and exact group/provider/API/endpoint/reasoning/xhigh checks remain. Typed entries require `type: chat`; legacy entries may omit type but cannot specify another type. Locking, metadata trust, credential handling and controlled failure reporting are unchanged. Extracted real wrappers now participate in caller-gating regressions.
- **TASK-61:** required current baseline replaces `resolving-merge-conflicts` with `pr`. A separate historical-name list feeds inventory, cleanup and Pi ownership even without previous records, not ordinary deletion. Snapshot/report/both-copy/source-lock validation and promotion remain unchanged. All 37 required-name omissions fail with an extra future name maintaining cardinality. Ordinary historical preservation, opt-outs and identical-versus-modified Pi duplicate behavior have regressions.
- **TASK-62:** the real probe adds only exact equality with `opencode v${release}` after existing whitespace normalization. Native success, isolation, byte verification, timeout/output bound and restoration remain unchanged. Regressions inject native results/errors at the process boundary; OpenCode is never executed.
- Go and skills identical-helper contracts pass. OpenCode was regenerated with the existing generator; `--check` passes. Setup versions are macOS 260, Ubuntu 287, WSL 221, Pi 238, Bazzite 139 and Windows 170. OpenCode core header is version 3.
- Implementation-stage README and CLAUDE edits described current versus historical skills and exact supported catalog/version formats. Publication integration retained upstream's concise README instead; the compatibility guidance remains in CLAUDE and this record. No default model, ordinary provisioning, platform/headless, npm security, BB or unrelated policy changes appear in the implementation diff.

Self-review covered the complete diff, generated/shared equivalence, fixture extraction and mock ordering, preservation rules, failure aggregation, and documentation. New fixtures contain only inert skill content and public model data. No new containment refusal or unexpected real effect was observed; this was not a syscall-wide effects audit. Historical incident uncertainty remains unchanged.

## Public-data provenance

- `tests/fixtures/pi-ai-0.99.2-muse.json` contains only the Muse entry and provenance, not Pi runtime code. A static JSON comparison exactly matched the entry in retained integrity-verified `pi-ai-0.99.2-opencode-go.json`. The retained package metadata integrity is `sha512-9RFOEdY+ZTJ1AI+UuAFs4RM0tF2Tje/R/CEv9gWTJHt0iTu8XHZs64U/EIZxNSllFmec/4HfwsOxYj1qQek9bg==`.
- `tests/fixtures/matt-pocock-skills.json` exactly matches all 37 `skills/**/SKILL.md` names in the retained public tree at `d81f3a183412e71a5b1e84ca21bc1a35eea03a60`. Both revision and name-set equality were checked, not merely cardinality.
- Evidence inputs remain at `/tmp/setup-log-investigation.7VFVExdy`. No downloads were needed. The temporary diagnostic test was not shipped wholesale.

## Contained red/green cycles

Every behavioral invocation used this exact prefix, with suites appended as listed below:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh \
  --tool-path /usr/bin:/bin
```

The runner performed mandatory compiler/filter self-tests, used private roots and stdio, and ran suites sequentially. Each retained root contains `compiler.log`, `sandbox-self-test.log`, per-suite logs and `results.json`. No containment safeguard or loader was weakened.

| Stage | Suites appended to the prefix | Artifact root | Result |
| --- | --- | --- | --- |
| Go red | `tests/setup-default-contract.sh tests/test_fixture_containment.py tests/pi-opencode-go-contract.sh tests/opencode-go-wiring-contract.sh` | `/tmp/setup-fixture-matrix-dr98hvd5` | Safety suites passed. Go: 24 methods, 13 failed subcases, 2 skips. Wiring: 5 methods, 6 failed typed-catalog subcases. |
| Go green | `tests/pi-opencode-go-contract.sh tests/opencode-go-wiring-contract.sh` | `/tmp/setup-fixture-matrix-gq7flp2p` | Both passed; Go 24 methods/2 skips, wiring 5/0. |
| Skills red | `tests/test_managed_skill_suite.py` | `/tmp/setup-fixture-matrix-wt0ourfl` | 32 methods, 69 failed expected-success assertions, 3 skips; reviewed current promotion reports `incomplete-suite`. |
| Skills green | `tests/test_managed_skill_suite.py tests/pi-skill-ownership-contract.sh tests/simple-english-skill-contract.sh` | `/tmp/setup-fixture-matrix-ev8fauxt` | All passed; suite 32 methods/3 skips. |
| OpenCode red | `tests/opencode-cli-contract.sh` | `/tmp/setup-fixture-matrix-o_ko0wsy` | Node: 130 tests, 125 passed, 4 failed, 1 skip. Caller suite not reached after Node failure. |
| OpenCode green | `tests/opencode-cli-contract.sh` | `/tmp/setup-fixture-matrix-9rehg_xh` | Node: 130 tests, 129 passed, 1 skip; callers: 7 passed. |

Go red evidence includes the exact typed-catalog rejection in the helper and all six wrappers, plus explicit legacy non-chat entries incorrectly accepted. Three later negative subcases initially inherited the mutated fixture auth from earlier failed subcases; fixture auth is now reset for each case, removing cascading red noise without changing assertions. OpenCode red includes named-output direct/staged failures and two promotion regressions stopping too early at the first probe.

## Final affected matrix

Artifact root: `/tmp/setup-fixture-matrix-x0r0i4o2`. **21/21 suite entries returned 0**, with skips explicitly listed below. Exact invocation:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh \
  --tool-path /usr/bin:/bin \
  tests/setup-default-contract.sh \
  tests/test_fixture_containment.py \
  tests/pi-opencode-go-contract.sh \
  tests/opencode-go-wiring-contract.sh \
  tests/test_managed_skill_suite.py \
  tests/pi-skill-ownership-contract.sh \
  tests/simple-english-skill-contract.sh \
  tests/opencode-cli-contract.sh \
  tests/ai-coding-agent-contract.sh \
  tests/pi-model-defaults-contract.sh \
  tests/shared-node-runtime-contract.sh \
  tests/pi-package-maintenance-contract.sh \
  tests/pi-profile-permissions-contract.sh \
  tests/headless-contract.sh \
  tests/telegram-alerts-contract.sh \
  tests/setup-reliability-contract.sh \
  tests/weekly-log-audit-regressions.sh \
  tests/paseo-non-management-contract.sh \
  tests/pending-reboot-contract.sh \
  tests/test_macos_clt.py \
  tests/test_homebrew_results.py
```

| Suite | Reported coverage and skips | Seconds |
| --- | --- | --- |
| setup-default | 3 + 5 methods, no skips | 2.1 |
| fixture containment | 8 methods, no skips; actual Bash extraction and full PowerShell parse/136 definition parses | 7.0 |
| Pi Go | 24 methods, 2 optional installed catalog/native lock skips | 23.2 |
| Go wiring | 5 methods, no skips | 5.0 |
| managed suite | 32 methods, 3 optional native CLI discovery/snapshot and dotfiles skips | 147.5 |
| Pi skill ownership | Bash contract passed | 6.2 |
| managed/retired agents | Bash contract passed | 16.8 |
| OpenCode CLI | 130 Node tests: 129 passed, 1 optional installed npm Windows shim skip; 7 caller methods passed | 49.9 |
| AI agents | Bash contract passed | 6.4 |
| model defaults | 4 Python methods and PowerShell fixtures passed | 7.6 |
| shared runtime | 18 methods/1 mise skip; 1 convergence method skipped; PowerShell 1,403 assertions twice with native mise inventory skipped each time | 83.7 |
| Pi packages | 30 methods, 2 optional dotfiles/installed registry probe skips | 111.6 |
| Pi profile permissions | 21 methods, 2 native Windows ACL/handle-race skips | 14.4 |
| headless | 7 methods, no skips | 4.8 |
| Telegram | Five Bash and PowerShell environment contracts passed | 1.0 |
| reliability | 22 CLT methods, PowerShell logging/reliability fixtures and 9 Homebrew methods passed | 65.3 |
| weekly | Contract passed, repeats managed suite: 32 methods/3 skips | 150.0 |
| Paseo non-management | 5 methods, 1 cross-repository dotfiles skip | 3.1 |
| pending reboot | Contract passed | 0.2 |
| macOS CLT | 22 methods, no skips | 7.5 |
| Homebrew results | 9 methods, no skips | 0.4 |

Mise is not exposed in the selected explicit tool PATH. Optional installed-code and cross-repository environment variables were deliberately not enabled. Counts above are suite-reported methods/tests, not a claim that repeated nested suites are independent coverage.

## Static checks and remaining validation gap

`/tmp/setup-fixture-matrix-x0r0i4o2/static-checks.log` records successful checks:

```bash
/usr/bin/shellcheck mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh
for script in mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh; do /bin/bash -n "$script"; done
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tools/embed-opencode-cli.py --check
env -i PATH=/usr/bin:/bin /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node --check lib/opencode-cli.cjs
env -i PATH=/usr/bin:/bin /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node --check tests/opencode-cli.test.cjs
git diff --check
```

Changed Python files were parsed with `ast.parse`, without execution or bytecode writes. PowerShell parsing of the entire `win.ps1` and its 136 definitions passed inside the final containment suite, without running the entry point.

**Unavailable:** no trusted installed Markdownlint was found on PATH or in the checked global Node/Bun installation roots. No linter/runtime was fetched or an untrusted cache executed. Markdown changes were self-reviewed, but automated Markdownlint is not claimed. Parent must supply an approved existing tool or explicitly accept this validation omission before closing the tasks.

Linux PowerShell is not native Windows evidence. Native macOS, Windows, ARM, real artifact/application execution, installed Pi lock/catalog interoperability, native skills selection, dotfiles integration and host continuity/rollout remain unverified or out of scope. No live rollout is needed to validate these offline code fixes; a separately authorized machine run is needed to establish native behavior. The unrelated BB failure remains unresolved and out of scope.

## Publication integration

The user requested these changes in remote main. Fetched upstream `cf1ac23` (the concise-README change) before publication and integrated its complete commit. Resolved the README conflict in favor of that human-facing introduction; resolved CLAUDE by combining the exact-version guidance with upstream's repaired ADR/code pointers. Retained upstream's test changes, which remove README-prose assertions without altering behavioral boundaries. No production-code integration conflict occurred.

Upstream already owns unrelated TASK-60. Used the Backlog CLI to demote the local Go task to DRAFT-1, then promote it as TASK-63, preserving its implementation/evidence records. Updated this report and the plan; upstream TASK-60 remains untouched. Earlier references to branch-local TASK-60 in implementation artifacts mean the Go compatibility task, not the upstream README task.

Re-read the containment audit/incident and reviewed the seven upstream test diffs before execution. Re-ran the full 21-entry command above with these four additional affected suites appended:

```text
tests/claude-code-installation-contract.sh
tests/gitea-client-installation-contract.sh
tests/ntn-installation-contract.sh
tests/pi-prose-contract.sh
```

Result: **25/25 entries returned 0**, including the mandatory kernel filter/self-test and extraction contracts. Private integrated-source artifacts: `/tmp/setup-fixture-matrix-q5f497vx`. The earlier optional skips remain: installed Pi catalog/native lock, native skills CLI/dotfiles, npm shim, mise/convergence, package registry/dotfiles, native Windows ACL/race, and Paseo cross-repository checks. The added Pi prose suite reports 22 methods with no skips. No native rollout, new containment refusal, or unexpected real effect was observed; this is not a syscall-wide effects audit.

Publication checks use existing system tools instead of the repository hooks' unrestricted `bunx` resolution and uncontained suite loop. Set `LEFTHOOK=0` only for publication Git commands; do not change installed hooks or repository hook configuration. Run ShellCheck/syntax, generator consistency, staged secret scanning and whitespace checks manually. Trusted Markdownlint is still absent: discovered cached entry points are world-writable and were not executed. Existing system CommonMark parsing/local-link checks and manual Markdown review are supplemental checks, not a Markdownlint pass. Tasks remain open for that specific validation gap.

`/tmp/setup-fixture-matrix-q5f497vx/publication-static.log` records successful publication ShellCheck/Bash syntax (five entry points plus six integrated contracts), generator consistency, Node syntax, five Python AST parses, CommonMark parsing/closed fences/12 local links across four documents, and whitespace checks. Full PowerShell parsing passed in the integrated containment suite. `/usr/bin/gitleaks protect --staged --no-banner --redact` also passed with no leaks. No repository hook configuration was changed; the publication push is non-force.
