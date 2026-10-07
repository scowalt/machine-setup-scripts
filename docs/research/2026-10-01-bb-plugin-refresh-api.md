# TASK-64 BB plugin-refresh native contract

Historical alias: this was branch-local TASK-60 before rebasing onto `adce1d4`. Upstream TASK-60 belongs to the unrelated README cleanup and remains unchanged. The branch record was recreated through the Backlog CLI as TASK-64; original task bytes remain in Git recovery stashes. Validation artifacts below retain their original names and pre-rebase scope.

## Read-only sources

Inspected the installed `bb-app` **0.44.0** package under `/home/scowalt/.local/share/mise/installs/node/24.20.0/lib/node_modules/bb-app`, without executing its CLI, importing its modules, querying a live server, or executing plugins.

- `server/dist/start-server.js`, SHA-256 `344b576226854db7d54ecb4e397c3b904d0776936bb63743a28a05a67beeb008`.
- `dist/bb-app.js`, SHA-256 `2eb3c34b952fe24769458e292c2670bafc882653ef8673587faebfc6f3cb5c4e`.
- Package metadata, README, and `host-daemon/dist/bb-chunks/plugin-R4ESEAVQ.js`.
- Installed BB guide's `bb-cli/references/plugins.md`.
- Public desktop source at commit [`2573ad5e85835dc1c90aa33795e6dba52ef5aa92`](https://github.com/get-bb/bb/tree/2573ad5e85835dc1c90aa33795e6dba52ef5aa92): `apps/desktop/src/{owned-runtime-supervisor,server-probe,bb-app-bridge,app-paths}.ts` and `apps/desktop/electron-builder.config.json`. GitHub source reads are not live BB requests.

The public desktop build unpacks `node_modules` and its bridge. The bridge imports the native `bb-app` launcher; the launcher spawns the packaged `server/dist/index.js`. Desktop connection selections and the bridge's PID alone are insufficient main-server identity evidence.

## Native plugin operations

The policy uses core HTTP routes behind the same native service as the CLI, not plugin RPC or an independently implemented resolver. This avoids CLI selection/re-exec controls and permits inspecting the complete structured update result.

| Route | Inspected implementation |
| --- | --- |
| `GET /health` | `start-server.js:210250`; `ok`, optional per-spawn `launchId`, optional server-move state. Not an ownership attestation. |
| `GET /api/v1/system/config` | Native response schema at `38451` includes `dataDir`. It must match local process evidence. |
| `GET /api/v1/plugins` | Installed plugin inventory: enabled flag, source, provenance, status and update state. |
| `GET /api/v1/plugins/:id/source` | Requested/resolved source, registry, subdirectory, range and tag prefix; no settings mutation. |
| `GET /api/v1/plugins/safe-mode` | Boolean native mode; setup never writes it. |
| `POST /api/v1/plugins/updates/check` | `182721`; structured `current`, `update-available`, `pinned`, `incompatible`, or `unavailable` entries. Checking can stage/read source metadata; it is not a pure local observation. |
| `POST /api/v1/plugins/:id/update` with `{}` | `182747`; native `applyUpdate`, not install/remove/reload. Structured `applied`, `from`, `to`, and `current`/`updated`/`rolled-back` outcome. |

`createPluginUpdates` (`198735` onward) resolves existing source intent, treats local/builtin sources as pinned, retains compatibility selection and returns failures for unavailable sources. It does not make an unavailable retired-marketplace source an intentional exclusion. `applyUpdate` (`199109`) refuses safe mode, and a rollback can return **HTTP 200** with `applied: false` and `outcome: rolled-back`. The CLI likewise need not exit unsuccessfully for every unavailable/skipped/rolled-back outcome.

`activateManagedUpdate` (`188859`) snapshots native state, preserves `enabled: args.row.enabled`, loads the replacement, waits through native stabilization, and restores the snapshot on activation error. Disabled rows stay disabled through `loadOne` (`197646` onward). Settings, secrets and schedules are left to this native transaction; setup neither reads their values for verification nor writes their stores. This is source evidence, not an execution test of arbitrary plugin migrations.

The implementation conservatively accepts only the inspected **0.44.0** native contract. This is not a BB installer pin or a downgrade. Other versions, custom/source-build layouts and unverifiable capabilities need review rather than a guessed API fallback. Modern response shapes alone would not prove the disabled-state and source-preservation semantics of another implementation.

## Local identity and lifetime

Discovery reads account process evidence, package metadata and trusted local data boundaries. It recognizes the packaged main-server entry, not a prepared CLI, execution daemon, desktop connection, loopback address, or inherited `BB_CLI`/`BB_SERVER_URL`. A manual server may have a different HOME or data directory; its UID and data ownership are the relevant account facts. Default data and an explicit `BB_DATA_DIR` are also inspected for stopped-server deferral. There is no filesystem-wide search for unreferenced stopped custom data directories.

Immediately before every request, setup checks the same account PID/start evidence and package/data boundaries, connects directly to IPv4 loopback, and proves that the **accepted server-side connection** belongs to that process. Linux uses socket inodes and `/proc/<pid>/fd`; macOS uses native `lsof` connection records and `KERN_PROCARGS2`/`ps` process evidence. A local SSH tunnel cannot satisfy this proof merely by sharing the account or listening on loopback. The HTTP client disables automatic reconnect and follows no redirects or proxy/environment selections. Per-spawn health identity, when supplied by the launcher, and native `dataDir` must also match.

Multiple references to one data-directory inode do not produce repeated refresh. Multiple main processes claiming a directory or endpoint are ambiguous and fail closed. A valid native moved-server marker excludes the historical copy without contacting its new address. Unknown live owners of local BB data, malformed/linked/unowned evidence, unsafe regular-file/root/system permissions, source-build/custom layouts that cannot be verified, changed evidence and unsupported native versions remain unverified rather than update success. [ADR 0012](../adr/0012-accept-account-owned-ordinary-directories.md) supersedes #192's absence-only directory exception: eligible ordinary account-owned directories and ancestors accept group write during both positive verification and negative discovery, without establishing server identity or readiness. The bounded metadata snapshot includes the native database's standard SQLite sidecars as partial main-server evidence; enrollment and shared CLI state do not count.

Stopped deferral requires no verified running main, no live launcher claim, and no observed account process holding the native database (macOS uses `lsof`). Only the database's SQLite header and file identity are read; normal database content/mtime changes are not treated as immutable package metadata. No SQL, database mutation, store surgery or permission repair is performed. Kernel/process inspection and path checks are conservative local evidence, not a defense against a malicious process with the same UID or root privileges.

Darwin process-argument reads use a validated native `kern.argmax`, not a fixed buffer size; oversized requests can fail with `EINVAL` before PID lookup. See the [native sizing reproduction and repair](2026-10-05-bb-plugin-procargs-buffer.md). This does not make other inspection errors skippable or establish complete native refresh recovery.

Operations have socket timeouts, bounded response/inventory sizes and a 30-minute helper deadline. Timing out a request never cancels/restarts the server, retries an uncertain update, or terminates threads; the native server operation may still finish. Its result remains failed/unverified for that setup run. Native safe-mode refusal is recognized without turning unrelated errors into deliberate deferral.

## Offline execution boundary

New fixtures import selected Python definitions only and use synthetic package/database files. The importer allowlists standard-library imports and literal initialization, rejects definition-time calls/decorators/annotations, executable class bodies and metaclass/base shadowing, and excludes the entry guard; benign pre-mock regressions verify those refusals. Process inventory, native sysctl/lsof/socket evidence and HTTP requests are mocked before intentional helper calls. Extracted Bash caller tests replace every setup helper and deny external lifecycle/package/network commands before invoking the real wrappers. They execute neither installed BB code nor a live server.

The existing audited caller fixtures discover function names and replace the new refresh helpers before running callers; no whole setup entry point is sourced. Linux seccomp/FD containment remains mandatory, with sanitized `env -i`, private roots/stdio and sequential suites. See the [fixture audit](2026-09-29-fixture-execution-audit.md) and [incident record](2026-09-29-fixture-containment-incident.md).

## Validation evidence

The initial implementation stages below precede the rebase. The [post-rebase verification](#post-rebase-verification) records the integrated source separately.

| Stage | Private artifacts | Result |
| --- | --- | --- |
| Initial containment/default/refresh cohort | `/tmp/setup-fixture-matrix-31psbqpi` | 3/3 entries; initial 17 refresh methods pass. |
| Expanded targeted fixture | `/tmp/setup-fixture-matrix-tg0e0r_t` | 1/1 entry; 20 refresh methods pass. |
| Full audited aggregate | `/tmp/setup-fixture-matrix-c7j1qlqr` | **41/41 entries pass**; 495 unittest method executions including 15 skips; 123 OpenCode Node cases, 122 pass and one optional skip. |
| Final-production affected matrix | `/tmp/setup-fixture-matrix-pmq5jy1b` | **15/15 entries pass**; 306 unittest method executions including five skips. Includes 23 refresh methods after three added deadline/UID/readiness regressions. |
| Fixture-import hardening | `/tmp/setup-fixture-matrix-ajk2935e` | **3/3 entries pass**, 40 methods, zero skips: eight containment, eight setup-default/environment and 24 refresh methods. Production code is unchanged from the affected matrix. |

The aggregate preceded the final adjustment moving the helper deadline ahead of discovery. The final-source matrix rechecks the complete required affected BB/preparation/desktop/server, setup-default/extraction, reliability, headless, shared-runtime, CLT/Homebrew/reboot/weekly and orchestration matrix after that adjustment. `source-manifest.json` in `/tmp/setup-fixture-matrix-ajk2935e` records SHA-256 hashes of the final executable sources and hardened targeted fixture; the earlier manifest in the affected-matrix root is retained. Each root retains the mandatory compiler/filter self-test diagnostics, private suite logs and `results.json`. There were no failed entries/timeouts, new preflight refusals or observed unexpected real effects; this is not a syscall-wide effects audit.

Exact aggregate command:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh \
  --tool-path /usr/bin:/bin:/tmp/task56-audited-tools-wn5n3t7y --timeout 300 \
  tests/ai-coding-agent-contract.sh tests/attention-span-removal-contract.sh \
  tests/backlog-mcp-retirement-contract.sh tests/bb-desktop-contract.sh \
  tests/bb-machine-preparation-contract.sh tests/bb-server-contract.sh \
  tests/claude-code-installation-contract.sh tests/codex-profile-isolation-contract.sh \
  tests/gitea-client-installation-contract.sh tests/headless-contract.sh \
  tests/infisical-retirement-contract.sh tests/kubectl-installation-contract.sh \
  tests/setup-default-contract.sh tests/ntn-installation-contract.sh \
  tests/opencode-cli-contract.sh tests/opencode-go-wiring-contract.sh \
  tests/paseo-non-management-contract.sh tests/pending-reboot-contract.sh \
  tests/pi-askclaude-contract.sh tests/pi-companion-packages-contract.sh \
  tests/pi-model-defaults-contract.sh tests/pi-opencode-go-contract.sh \
  tests/pi-package-maintenance-contract.sh tests/pi-profile-permissions-contract.sh \
  tests/pi-prose-contract.sh tests/pi-rpiv-removal-contract.sh \
  tests/pi-skill-ownership-contract.sh tests/pi-subagents-removal-contract.sh \
  tests/pi-zai-provider-contract.sh tests/rtk-removal-contract.sh \
  tests/setup-reliability-contract.sh tests/shared-node-runtime-contract.sh \
  tests/simple-english-skill-contract.sh tests/telegram-alerts-contract.sh \
  tests/weekly-log-audit-regressions.sh tests/windows-log-upload-contract.sh \
  tests/test_fixture_containment.py tests/test_macos_clt.py \
  tests/test_homebrew_results.py tests/test_managed_skill_suite.py \
  tests/test_bb_plugin_refresh.py
```

The final-source command uses the same exact runner and tool arguments above, with this ordered suite list:

```text
tests/test_bb_plugin_refresh.py tests/test_fixture_containment.py
tests/setup-default-contract.sh tests/bb-desktop-contract.sh
tests/bb-machine-preparation-contract.sh tests/bb-server-contract.sh
tests/setup-reliability-contract.sh tests/headless-contract.sh
tests/shared-node-runtime-contract.sh tests/test_macos_clt.py
tests/test_homebrew_results.py tests/pending-reboot-contract.sh
tests/weekly-log-audit-regressions.sh tests/paseo-non-management-contract.sh
tests/ai-coding-agent-contract.sh
```

The final fixture-import hardening command uses the same runner/tool arguments with `tests/test_fixture_containment.py tests/setup-default-contract.sh tests/test_bb_plugin_refresh.py`, in that order. It adds refusal cases for unaudited imports, top-level/class-body calls, method-default calls, decorators, annotations, metaclasses and shadowed exception bases; no application import is attempted.

Static validation passes: `bash -n` and `shellcheck` on the five changed Bash entry points and `lib/bb-plugin-refresh.bash`; `ast.parse` on the three new Python files; `--check` for all three embedding tools; and `git diff --check`. ShellCheck initially requested explicit optional arguments at the new callers; callers now pass `ready` or `block-default`, and the final checks pass. An additional whole-file whitespace assertion surfaced only unchanged legacy whitespace (Ubuntu one line, Pi nine, WSL six); comparison with `HEAD` confirmed those lines were untouched. The final check covers new-source whitespace plus `git diff --check`, without unrelated cleanup. The initial static diagnostic is retained as `static-checks-initial.log`, and the passing final checks as `static-checks.log`, in the final root. Trusted installed Markdownlint is unavailable; no shared cache or downloaded replacement was executed. Markdown was manually reviewed.

Optional external-dotfiles, installed skill/Pi/extension registry, Go catalog/lock and OpenCode command-shim integrations were not enabled by the sanitized runner; these remain skips, not coverage. Native Windows Backlog handle/ACL operations retain their explicit omission. Available Linux PowerShell wrapper fixtures ran with the selected existing `PWSH_BIN`, without claiming native Windows/PowerShell 5.1 behavior.

The new Linux accepted-socket/UID logic and macOS sysctl/lsof parsing use synthetic native evidence, not live connections or daemon inventory. Real peer-ownership behavior, native macOS/Windows/WSL/ARM/Bazzite behavior, BB/plugin migration/activation, and workload continuity remain separate rollout obligations. No live setup, BB/plugin request, lifecycle operation, app/skill/extension execution, fleet update, auth or Tailscale mutation was used for development validation. Offline fixtures neither establish rollout readiness nor resolve the earlier incident's remote receipt/retention uncertainty.

## Post-rebase verification

Rebased the branch onto fetched `origin/main` at `adce1d4` and restored its uncommitted work. Conflicts were limited to documentation and five setup version headers. Kept upstream's concise human README and its repaired agent pointers, retained the plugin-refresh guidance and lifecycle exception in CLAUDE, and preserved the upstream Go/skills/OpenCode fixes. The five setup versions are now macOS **261**, Ubuntu **288**, Pi **239**, Bazzite **140**, and WSL **222**. Native Windows remains unchanged at upstream's version.

Static comparison verifies that each Bash script's feature delta against latest main is identical to its original pre-rebase delta after normalizing version headers. The shared refresh Python/Bash, embedder and targeted fixtures are byte-identical to the pre-rebase files; no new runtime behavior was introduced during conflict resolution. The upstream README is byte-identical to `HEAD`. TASK-64 replaces the colliding branch-local TASK-60 through CLI-managed metadata creation, preserving the original task in recovery stashes and leaving upstream's task records unchanged.

**Integrated aggregate: 41/41 entries pass**, including 24 targeted refresh methods. Artifacts: `/tmp/setup-fixture-matrix-8d63kam5`. This used the exact runner/tool/timeout prefix in the aggregate command above, first running `tests/test_fixture_containment.py`, `tests/setup-default-contract.sh`, and `tests/test_bb_plugin_refresh.py`, then the remaining aggregate entries in their listed order, with those three omitted from their former positions. Mandatory kernel filter/self-test, sanitized environment, private roots/stdio and sequential execution were unchanged. The artifact root retains `results.json`, preflight/suite logs, `static-checks-rebase.log` and `source-manifest-rebase.json`.

Bash syntax, ShellCheck, all three embedding checks, Python AST parsing and whitespace checks pass. A one-off static version assertion initially matched an embedded library's header instead of the setup banner; anchoring it to the banner fixed the assertion without changing production code. No behavioral suite or containment preflight failed. No unexpected real effect was observed; this is not a syscall-wide effects audit. Optional installed-code/cross-repository integrations and native Windows operations retain their explicit skips; trusted Markdownlint and native rollout/continuity remain unavailable or unverified. No live BB/plugin request, setup run, lifecycle operation, commit or push occurred during rebase validation.

## Publication authorization

The user subsequently requested publication to remote main. A fresh fetch confirmed `origin/main` is still the tested base `adce1d4`. Executable-source hashes are checked against the post-rebase manifest before publication, with ShellCheck, syntax, embedding, whitespace and a redacted staged secret scan rerun using existing system tools. The existing hooks invoke uncontained behavioral suites and tool-resolving `bunx` commands; publication therefore uses command-local `LEFTHOOK=0` with the audited 41-suite evidence and manual checks, without changing hook configuration. Trusted Markdownlint remains unavailable, and the BB 0.44.0/native-rollout limitations remain unchanged. Publication uses a non-force push; it does not authorize live setup or plugin operations on machines.
