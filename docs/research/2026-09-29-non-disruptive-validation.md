# TASK-57 implementation and offline validation

Status: parent accepted AC1–9 against the post-review offline source/evidence and committed it as `df7918b`. Integration with upstream OpenCode fixes `4ece5ef` and `e169f8d` now passes the affected contracts and refreshed 40-entry contained aggregate; the resolved source is ready for parent integration review. TASK-57 remains **In Progress**; AC10 and completion remain held for the user's disposition of the incident exception. Native continuity is unverified. The earlier [fixture incident](2026-09-29-fixture-containment-incident.md) remains an explicit exception to the no-live-effects requirement, not something subsequent passing tests erase.

Historical alias: this work was branch-local **TASK-56**, renumbered through Backlog CLI to **TASK-57** after upstream introduced an unrelated TASK-56. Historical `/tmp/task56-*` paths and incident chronology retain the original identifier. Parent exclusively owns Git authentication, merge completion and publication; this integration work changes source/evidence only.

## Integrated-source verification

Only six version headers conflicted. The merge preserves upstream OpenCode HTTP negotiation, controlled diagnostics and exclusive-primary-group trust checks alongside the reviewed default scheduling, fixture authorization and logging behavior. Source comparisons confirm that each entry point differs from `df7918b` only in its generated OpenCode block and requested version header; all five upstream policy/Node/native-proof files remain byte-identical to `e169f8d`. The auto-merged caller retains all upstream assertions plus the local real maintenance initializer/import. Parent's `CONTEXT.md` and upstream's unrelated TASK-55/TASK-56 records are unchanged.

[The additional fixture audit](2026-09-29-fixture-execution-audit.md#upstream-integration-audit) preceded all integration behavior runs. Both runs used the unchanged sanitized runner/filter/self-test/FD boundaries, existing explicit tools, private roots and 300-second per-suite bounds. No optional installed-code integrations or actual host Homebrew proofs ran.

| Integrated stage | Evidence root | Result |
| --- | --- | --- |
| Affected contracts | `/tmp/setup-fixture-matrix-szh8p7l6` | 5/5: OpenCode, non-disruptive, CLT, Homebrew results and extraction/containment |
| Full audited aggregate | `/tmp/setup-fixture-matrix-u3o1b6du` | **40/40 entries**, zero failures/timeouts; same 36 shell/four direct Python entries as the exact aggregate command below |

The affected command was:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh --tool-path /usr/bin:/bin:/tmp/task56-audited-tools-wn5n3t7y --timeout 300 tests/opencode-cli-contract.sh tests/non-disruptive-setup-contract.sh tests/test_macos_clt.py tests/test_homebrew_results.py tests/test_fixture_containment.py
```

The integration aggregate repeated the **exact 40-entry aggregate command** recorded below, without optional integrations or altered arguments. `results.json` and all 40 logs in `/tmp/setup-fixture-matrix-u3o1b6du` are the integrated-source evidence; `/tmp/setup-fixture-matrix-ptafh82r` remains pre-integration evidence only.

- Non-disruptive: **16 methods**, no skips. Extraction/containment: **8 methods**, no skips, five Bash trees and **142** PowerShell function definitions. CLT: **22 methods**; Homebrew results: **9 methods**; OpenCode callers: **7 methods**, all without skips.
- Aggregate unittest summaries: **483 reported methods including 15 skipped executions** (12 distinct cases with three weekly repeats), not 483 unique passes.
- Expanded upstream OpenCode Node suite: **98 cases, 97 passed, one optional cmd-shim skip**, zero failures. This supersedes the historical 44-case count only for the integrated source.
- The same optional/native skip reasons in the table below remain: **15 unittest skips, one Node skip and one separate Backlog native-Windows handle/ACL diagnostic omission**. Linux PowerShell remains neither native Windows nor PowerShell 5.1 proof.
- Integrated static checks pass: Bash syntax/ShellCheck 0.9.0 on **21 files** (adding upstream's Bash wrapper), Python AST on **25 files**, both embed tools with `--check`, actual Windows AST through containment, whitespace, and manual/local-link Markdown review. Markdownlint remains blocked, not passed; its mutable cache was not executed or altered.
- `/tmp/setup-fixture-matrix-u3o1b6du/integrated-source-sha256.json` records **60 source files** (the original 55 plus three OpenCode policy files, the Node suite and native-proof fixture). Manifest SHA-256: `61616eb5781571f5e2d33e9f10ad724fe9ea48ae2492f1ca2fd9b9c14ef8c590`. `integration-static.json` records exact static-check inventories and preservation assertions; `shellcheck.log` is empty. No workspace Python cache was created.

No new containment refusal or unexpected real effect was observed. Seccomp still does not isolate filesystem/process effects, and these runs are not a syscall-wide effects audit. All earlier evidence remains preserved. There was no collector follow-up, live rollout, package/service/auth change, legacy-hook execution or tool installation. Parent alone owns merge completion, authentication and publication; this child did not commit, push or create a PR. TASK-57 remains In Progress, with parent-accepted AC1–9 and unchecked AC10. Publication authorization does not resolve the original incident exception.

## Implemented behavior

- All six callers separate ordinary observation/deferral from explicit invocation-only maintenance. Known BB contexts refuse maintenance; environment files cannot authorize it.
- System/package/bootstrap, runtime, BB, agent/profile/auth/skill/cleanup, dotfile, network/service and updater changes are deferred with their dependencies. Direct shared mutation boundaries also require authorization. Missing software and idle/unknown/racing consumers are not exemptions.
- Default work is limited to platform/account gates, data-only flags, bounded service observations, passive reboot reporting, safe absent Code creation, setup-owned locks/logging and existing log transport. Actual failures stay nonzero through independent work and finalization; deferred state is never presented as current/update freshness.
- Bash and PowerShell dotenv readers handle the actual commented BB_SERVER/MACHINE_TYPE template lines, literal credential hashes and quoted spaces without evaluation. Malformed supported-key values fail with controlled messages. Ubuntu process BB_SERVER precedence and exact headless behavior remain.
- Default managed BB readiness never resolves Node/mise or an app CLI. It requires a root-owned non-writable native system Python ELF under `/usr/bin`, uses isolated/no-site startup, fixed systemd observation, private metadata, process identity and bounded numeric-loopback HTTP GETs without proxy/redirect behavior. Missing trustworthy prerequisites fail observation without repair. The fixtures mock process/systemd/HTTP observations before invoking this extracted program; no real health request was sent.
- Windows ACL gating uses trusted CLR platform detection, compatible with Windows PowerShell 5.1, rather than mutable `$env:OS`. Linux fixtures exercise a synthetic native-Windows branch and an inert Get-Acl failure, not real Windows ACL semantics.
- Bash logging now reserves a private per-run directory using trailing-X `mktemp -d`, then exclusively creates a mode-0600 `.log` leaf without rename-over or hardlink promotion. Existing regular/link/hardlink candidates are refused. Local paths are one level deeper; the unique filename format, multipart field/endpoint and bytes are unchanged. A strict BSD-style fixture exercises the real macOS helper; this is not native Apple evidence.
- Windows ordinary logger safety/startup failures now aggregate separately from task dispatch: real safe service/Code/deferral/reboot work continues, the original failure remains nonzero, and finalization runs once. Unstarted transcript state cannot upload or advertise a partial file as finalized; the file itself is preserved. Maintenance retains fail-before-dispatch on logger errors and original task-failure/finalization behavior after a successful start.
- Canonical shared policy and embed/check tooling preserve standalone script use. Pre-integration post-review versions: macOS **256**, Ubuntu **283**, Pi **234**, Bazzite **135**, WSL **217**, Windows **166**. Integrated versions: macOS **257**, Ubuntu **284**, Pi **235**, Bazzite **136**, WSL **218**, Windows **167**.

## Staged execution history

Every resumed behavioral invocation used the sanitized runner, explicit existing runtimes, fresh private roots, mandatory kernel filter/self-test, safe stdio/FD handling and a 300-second per-suite bound. The filter was not weakened. No optional installed-code integration variables were enabled. [The execution audit](2026-09-29-fixture-execution-audit.md) records loader/tool boundaries; containment does not isolate filesystems or processes.

| Stage | Evidence root | Result and disposition |
| --- | --- | --- |
| Initial actual-source selection | `/tmp/setup-fixture-matrix-fhmzyugb` | One ordinary extractor error: legitimate subshell-form Bash function was unsupported. No sourceable tree emitted. PowerShell AST and synthetic boundaries passed. |
| Actual-source selection retry | `/tmp/setup-fixture-matrix-6t6rtstm` | 8 methods passed, no skips; all five actual Bash trees materialized and 141 then-current PowerShell functions parsed/selected without entry execution. Reciprocal brace/subshell validation and negative subshell-close tests retain the same boundary checks. |
| Initial cohort | `/tmp/setup-fixture-matrix-w21hkryx` | Non-disruptive, Attention Span and BB server passed; reliability correctly refused a fixture HOME created as 0775 by inherited umask. |
| Reliability repair | `/tmp/setup-fixture-matrix-y714wjed` | Passed after runner process umask was tightened to 077. Other-mask tests still set explicit masks. No production path guard changed. |
| First audited aggregate | `/tmp/setup-fixture-matrix-4xf2xh6d` | **38/40 passed**. BB service-trust fixture preconditions and model-default credential/path assertion failed; not final acceptance evidence. |
| Targeted repairs/review findings | `/tmp/setup-fixture-matrix-t_76xu6q` | Actual-source/containment, non-disruptive, model-default and complete BB preparation contracts all passed. Includes dotenv, Node-resolver and Windows platform regressions. |
| Pre-review aggregate (initially reported final) | `/tmp/setup-fixture-matrix-vghy85gm` | **40/40 entries passed** on the earlier source. This does not validate the subsequent logging fixes. |
| Post-review red regressions | `/tmp/setup-fixture-matrix-in1qh1ze` | 16 methods, seven assertion/subcase failures across three methods. Strict BSD-style template rejection and Windows skipped safe work were reproduced; new reservation collision cases were also initially red. |
| Post-review affected contracts | `/tmp/setup-fixture-matrix-_rsgab7_` | Non-disruptive, reliability, Windows upload, headless and actual-source/containment all passed after the fixes. |
| Refreshed post-review aggregate | `/tmp/setup-fixture-matrix-ptafh82r` | **40/40 entries passed**, zero failed/timed-out entries, including the additional shared-logger identity/private-directory assertions. Latest skips and omissions below. |

The shared-directory fixture now virtualizes only its outer ancestor metadata to model its intended shared-HOME scenario; real sandbox directories remain private. This forces the exclusive-group branch instead of legitimately taking the private-ancestor alternative. The model-default test removes only its known non-secret temporary HOME path before applying the unchanged credential-prefix assertion. Neither repair weakens production trust or removes preservation assertions.

No new containment incident or unexpected real effect was observed during these resumed stages. This is not a syscall-wide audit and does not retrospectively resolve the original incident.

### Exact commands

The two actual-source-only attempts used this command (different newly allocated roots):

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh --tool-path /usr/bin:/bin --timeout 300 tests/test_fixture_containment.py
```

The cohort, reliability-only retry and targeted-repair run used:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh --tool-path /usr/bin:/bin:/tmp/task56-audited-tools-wn5n3t7y --timeout 300 tests/non-disruptive-setup-contract.sh tests/attention-span-removal-contract.sh tests/setup-reliability-contract.sh tests/bb-server-contract.sh

env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh --tool-path /usr/bin:/bin:/tmp/task56-audited-tools-wn5n3t7y --timeout 300 tests/setup-reliability-contract.sh

env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh --tool-path /usr/bin:/bin:/tmp/task56-audited-tools-wn5n3t7y --timeout 300 tests/test_fixture_containment.py tests/non-disruptive-setup-contract.sh tests/pi-model-defaults-contract.sh tests/bb-machine-preparation-contract.sh
```

The post-review red regression and affected-contract run used these exact commands:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh --tool-path /usr/bin:/bin:/tmp/task56-audited-tools-wn5n3t7y --timeout 300 tests/non-disruptive-setup-contract.sh

env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh --tool-path /usr/bin:/bin:/tmp/task56-audited-tools-wn5n3t7y --timeout 300 tests/non-disruptive-setup-contract.sh tests/setup-reliability-contract.sh tests/windows-log-upload-contract.sh tests/headless-contract.sh tests/test_fixture_containment.py
```

All three pre-integration aggregate runs and the integrated-source aggregate used the following exact command, sequentially. The additional private tool directory contains only links to the existing audited mise, Chezmoi and Bun executables plus a private manifest; it does not expose a broad inherited user PATH. Native runtime mutations target copied fixture installations, not links to the real Node/npm prefix.

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh --tool-path /usr/bin:/bin:/tmp/task56-audited-tools-wn5n3t7y --timeout 300 tests/ai-coding-agent-contract.sh tests/attention-span-removal-contract.sh tests/backlog-mcp-retirement-contract.sh tests/bb-desktop-contract.sh tests/bb-machine-preparation-contract.sh tests/bb-server-contract.sh tests/claude-code-installation-contract.sh tests/codex-profile-isolation-contract.sh tests/gitea-client-installation-contract.sh tests/headless-contract.sh tests/infisical-retirement-contract.sh tests/kubectl-installation-contract.sh tests/non-disruptive-setup-contract.sh tests/ntn-installation-contract.sh tests/opencode-cli-contract.sh tests/opencode-go-wiring-contract.sh tests/paseo-non-management-contract.sh tests/pending-reboot-contract.sh tests/pi-askclaude-contract.sh tests/pi-companion-packages-contract.sh tests/pi-model-defaults-contract.sh tests/pi-opencode-go-contract.sh tests/pi-package-maintenance-contract.sh tests/pi-profile-permissions-contract.sh tests/pi-prose-contract.sh tests/pi-rpiv-removal-contract.sh tests/pi-skill-ownership-contract.sh tests/pi-subagents-removal-contract.sh tests/pi-zai-provider-contract.sh tests/rtk-removal-contract.sh tests/setup-reliability-contract.sh tests/shared-node-runtime-contract.sh tests/simple-english-skill-contract.sh tests/telegram-alerts-contract.sh tests/weekly-log-audit-regressions.sh tests/windows-log-upload-contract.sh tests/test_fixture_containment.py tests/test_macos_clt.py tests/test_homebrew_results.py tests/test_managed_skill_suite.py
```

### Refreshed post-review outcomes and skips

All **36 shell entries and four direct Python entries** listed in that command returned 0. This includes all five historical failures: Attention Span, Backlog retirement, BB preparation, Infisical retirement and reliability. `results.json` and the corresponding 40 suite logs under **`/tmp/setup-fixture-matrix-ptafh82r`** are the pre-integration post-review evidence; they do not validate the subsequent integration. All earlier roots remain historical artifacts.

- Non-disruptive contract: **16 methods**, no skips; real five Bash callers cover successful and failed health paths through reboot/log finalization; Linux PowerShell default wrapper and review regressions ran. Added logging cases cover two same-clock distinct logs with private directory/file permissions and status 23, preexisting regular/symbolic/hardlinked candidates, and five real Windows-wrapper failure subcases (unsafe directory/start failure in ordinary and maintenance modes, plus maintenance task failure). Service, transcript and transport operations are inert; actual safe Code creation and log guards/finalization are exercised inside temporary roots.
- Extraction/containment: **8 methods**, no skips; full five-source Bash materialization, actual PowerShell AST selection, synthetic boundary drift, both actual importer prefixes and inherited denial ran. Final PowerShell source contains 142 selected function definitions.
- Unittest summaries across the aggregate report **483 methods including 15 skips**; this includes repeated suites and is not a unique-case count.
- Node OpenCode suite: **44 cases, 43 passed, one skipped**, no failures.
- One additional Backlog diagnostic explicitly omits native Windows handle/ACL operations while its AST/C# compilation passes; it is not counted as a completed native test.

| Skip surface | Count in final aggregate | Explicit reason |
| --- | --- | --- |
| Paseo cross-repository source | 1 unittest | `PASEO_UNMANAGED_DOTFILES_SOURCE` intentionally unset |
| AskClaude cross-repository adapter settings | 1 unittest | `PI_ADAPTER_DOTFILES_SOURCE` intentionally unset |
| Go installed native catalog/lock | 2 unittest | `PI_GO_LOCK_MODULE` intentionally unset; no installed Pi code probe |
| Pi package adapter render/registry integration | 2 unittest | External dotfile source and installed Pi/npm extension probe intentionally disabled |
| Pi profile native Windows ACL/handle races | 2 unittest | Linux host is not native Windows |
| Native repair-to-skills convergence | 1 unittest | `PI_RUNTIME_DOTFILES_SOURCE` intentionally unset |
| Managed-suite native CLI discovery/snapshot and dotfile render | 6 unittest executions | Three optional cases with `MANAGED_SKILLS_CLI`/`PI_SKILLS_DOTFILES_SOURCE` unset, repeated by the weekly suite |
| OpenCode installed Windows cmd-shim comparison | 1 Node case | `OPENCODE_TEST_CMD_SHIM` intentionally unset |
| Backlog native Windows handle/ACL operations | 1 diagnostic omission | Requires Windows; compilation alone does not prove runtime behavior |

Thus there are **15 unittest skipped executions** (12 distinct skipped cases, three repeated by weekly), **one Node test skip**, and **one separately reported native-Windows diagnostic omission**. No optional live/installed integration was enabled to reduce those counts.

Native macOS/Bash 3.2/Apple tools, Windows PowerShell 5.1/ACLs/services/WinGet, ARM/Bazzite/WSL runtime behavior, GUI/sandbox behavior, cold boot, remote tailnet browser/WebSocket/local execution and real BB session continuity remain unverified. Linux PowerShell 7.6.6 coverage is not native Windows evidence.

## Static validation and blocker

- Bash syntax and ShellCheck 0.9.0 pass on all **20 modified/new shell files**, including the five entry points, canonical policy and changed shell fixtures. Post-review ShellCheck diagnostics are empty in `/tmp/setup-fixture-matrix-ptafh82r/shellcheck.log`.
- Changed/new Python sources parse successfully. Actual Windows source AST selection/parsing is included in the final contained aggregate.
- Canonical policy embedding is checked with `env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tools/embed-setup-policy.py --check`; the contracts also enforce affected shared-helper identity. Script version bumps are consistent.
- Documentation received manual review, **15 local link/heading checks across seven documents**, and `git diff --check`; these are **not equivalent Markdownlint coverage**.
- **Markdownlint blocked:** no native command was found. The only identified cached CLI, `/tmp/bunx-1000-markdownlint-cli@latest/node_modules/markdownlint-cli/markdownlint.js`, is mode **0777**, link count 2, beneath publicly searchable 0755 cache ancestors. It was not executed, chmodded or copied into apparent trust. No tool was installed/downloaded.
- Removed only the two identified task-generated, untracked regular `.pyc` files and their now-empty `tests/__pycache__/` directory after owner/link/name checks. All retained incident and test evidence under `/tmp` remains untouched.

## Acceptance-criterion disposition for parent review

Parent accepted AC1–9 against this pre-integration evidence with its explicit limitations; the table is not a completion declaration or unqualified native guarantee. Integrated-source verification is recorded separately. AC10 remains unchecked.

| TASK-57 criterion | Evidence/disposition |
| --- | --- |
| AC1: six default entry points and exact gates | Real Bash default caller tests and Linux PowerShell wrapper; headless/AI-agent/Paseo contracts pass. Native platform behavior remains a rollout limitation. |
| AC2: complete disruptive/dependency deferral, safe continuation | Shared real mutation-boundary fixtures return deferral before effects; BB/runtime/Pi/skill/caller contracts, failed-health/finalization regressions and post-review Windows logger-failure safe-work continuation cases pass. |
| AC3: not based on apparent inactivity | Default denial covers busy, idle, unrecognized and later-appearing consumer labels; no process-idleness or first-install authorization path. |
| AC4: invocation-only maintenance and preserved safeguards | Real initializer authorization/reset/refusal, malicious/saved env cases, unchanged preservation assertions and full affected maintenance contracts pass. |
| AC5: first-run and unhealthy services | Missing software remains deferred; health failures do not recover/restart, remain nonzero and reach independent reboot/log work. Fake Node/mise resolvers remain unexecuted. |
| AC6: independent updaters | Default callers never reach updater configuration; protected synthetic dotfile/updater bytes remain unchanged. Existing independent updater activity itself is outside setup's control. |
| AC7: honest results | Current/applied/deferred/failed summary fixtures pass; status 23, original Windows logger failures and maintenance task failures survive exactly-once finalization; failed-start partial logs remain unuploaded/unadvertised, and unqueried availability is explicit. |
| AC8: inert cross-platform callers/helpers | Final 40/40 aggregate with available Linux PowerShell, extracted actual sources, preservation and denied-command checks. Skips/native omissions above remain explicit. |
| AC9: affected contracts, static checks, identity | Final aggregate, syntax, ShellCheck and policy identity pass. Markdownlint has the genuine trusted-tool blocker above; manual/links/whitespace checks are not substitutes. |
| AC10: versions/docs and no-live-effects constraint | Version/doc portion implemented. **No-live-effects clause is not an unqualified pass:** the earlier fixture executed the ordinary Windows wrapper before mocks and made three known real upload attempts. Remote receipt/retention and additional telemetry uncertainty remain unresolved. Subsequent contained validation does not erase this exception. No commits, pushes, PRs, fleet operations or rollout were performed during that implementation/validation stage. Parent later committed the reviewed source under separate publication authorization; that does not erase the incident. |

## Changed-file map

The complete path/SHA-256 manifest for **55 changed/new source files** is retained at `/tmp/setup-fixture-matrix-ptafh82r/reviewed-source-sha256.json`; documentation and CLI-managed task metadata are additional changes.

- Entry points: `mac.sh`, `ubuntu.sh`, `pi.sh`, `bazzite.sh`, `wsl.sh`, `win.ps1`.
- Canonical scheduling/embedding: `lib/setup-policy.bash`, `lib/setup-policy.ps1`, `tools/embed-setup-policy.py`.
- New validation infrastructure: `tests/extract_setup_fixture.py`, `tests/fixture-no-network.c`, `tests/run-fixture-matrix.py`, `tests/test_fixture_containment.py`, `tests/setup_policy_fixture.py`, `tests/native_runtime_fixture.py`, `tests/non-disruptive-setup-contract.sh`, `tests/test_non_disruptive_setup.py`.
- Existing Bash/PowerShell contract fixtures: AI-agent, Attention Span, BB server/preparation, Claude, Tea, Infisical, reboot, RPIV, skill ownership, RTK, reliability, shared runtime, managed skills, Telegram, weekly and Windows logging. Changes are definitions-only imports, explicit real maintenance authorization, isolated native-runtime copies and updated caller/finalization expectations; versioned fixtures were bumped.
- Existing Python fixtures: BB desktop/directory/dotfile/preparation/permission/service-trust, CLT/Homebrew, Infisical/OpenCode callers, managed skills, Paseo, Pi model/package/profile and shared runtime/convergence. Production trust assertions are retained.
- Documentation: `README.md`, `CLAUDE.md`, the approved design, execution audit, incident chronology and this evidence report. TASK-57 metadata/notes are CLI-managed. The parent's preexisting `CONTEXT.md` changes remain untouched by this implementation.
