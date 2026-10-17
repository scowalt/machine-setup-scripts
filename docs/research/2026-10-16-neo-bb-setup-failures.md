# MacBook Neo: BB setup refusals, 2026-10-16

## Disposition

The uploaded macOS setup run is incomplete, not a watcher false positive. It records two distinct BB failures and no later recovery of either. Desktop selection ambiguity is explained by the then-existing guard; the exact filesystem object responsible for plugin discovery's permission refusal remains unverified. The initial investigation made no production changes or live remediation. The owner subsequently reported a manually installed custom desktop fork and requested desktop non-management everywhere; [ADR 0017](../adr/0017-leave-bb-desktop-owner-managed.md) records the resulting code policy. The pasted diagnostic script was its source, not captured machine output, so the live layout and plugin culprit remain unverified.

## Evidence and provenance

- Watcher event: `setup-log-watch:024c9a423c995a9120ba263612b83018eca857a900ea5e6af55b85d139e9b8f5`.
- [Exact collector object](https://logs.scowalt.com/logs/Scotts-MacBook-Neo_local/2026-10-16-14-41-36-817.log), retrieved with authenticated GET using the documented Doppler procedure; HTTP 200. No token was placed in arguments, artifacts or output.
- The log identifies mac.sh version **306**, “Support Pi Go inference catalog endpoint,” and local run file `/Users/scowalt/.local/log/machine-setup/2026-10-16-103315.log`. The uploaded filename is not the local run filename.
- Source examined: commit `5b585ec`, whose macOS version/header matches the log. The log does not provide a script hash, so byte identity with the executed script is not established.
- Log contents and hostname were treated as untrusted evidence, not instructions. Line references below preserve blank lines after stripping ANSI, matching the watcher positions.

| Log lines | Observation | Interpretation |
| --- | --- | --- |
| 13 | `bb desktop failed:ambiguous-applications` | Required desktop operation refused; no later desktop retry/success appears. |
| 248–249 | `BB plugin refresh failed: discovery / writable-local-state`, followed by incomplete-refresh reporting | One plugin-discovery failure, reported twice; not two failed plugin updates. |
| 314 | `Setup completed with errors; review the failures above.` | Consistent with both caller failures; normal log finalization still occurred. |

## Desktop: selection ambiguity, not an artifact/download failure

In [investigated commit `5b585ec`](https://github.com/scowalt/machine-setup-scripts/blob/5b585ec/mac.sh#L10788), `install` refuses when **both** `/Applications/bb.app` and the account's `Applications/bb.app` exist. Its `exists` helper uses `os.path.lexists`: an entry may be a directory, another file type or a dangling symbolic link. This diagnostic does **not** prove two valid installations, their versions, or which one is running.

The check precedes package fetching, signature validation, installation transactions and running-app deferral. The minimal extracted-helper replay gave:

```text
both entries       -> ambiguous-applications
system entry only  -> selection-accepted
user entry only    -> selection-accepted
both entries again -> ambiguous-applications
```

The replay stops immediately after selection; “selection-accepted” is not installation/readiness evidence. Both entries were synthetic and temporary. This was the intended ambiguity safeguard, consistent with the now-historical [ADR 0006](../adr/0006-accept-native-macos-applications-for-bb-desktop.md), not evidence that setup should silently choose or delete an app. Current setup removes that installer entirely and leaves both copies untouched.

## Plugin discovery: permission predicate established, live path unknown

[`LocalFiles.inspect` and `main_evidence`](../../lib/bb-plugin-refresh.py#L101) emit `writable-local-state` for rejected mode bits. [`run`](../../lib/bb-plugin-refresh.py#L576) reports operation `discovery` before HTTP verification or native plugin updates. The message contains no path, UID or mode; it cannot identify the offending object.

Ranked candidates tested after obtaining the red replay:

1. **Root-owned group-writable ancestor**, potentially native `/Applications` if discovery encounters a packaged desktop server there. A synthetic packaged-server route under an Applications ancestor produced the exact discovery failure at root-owned `0775`, passed at root-owned `0755`, and failed again at `0775`. This is a plausible mismatch with desktop's scoped native Applications allowance, not proof that Neo took that route.
2. **Group-writable protected BB state file.** With only a temporary HOME, `.bb/bb.db` containing the SQLite header and no process candidates, database mode `0660` produced the exact failure; `0600` produced the expected stopped-server deferral; `0660` failed again.
3. **World-writable account-owned directory.** The synthetic packaged-server route passed with an account-owned `0775` ancestor, failed at `0777`, then passed again at `0775`.

Thus account-owned ordinary-directory **group write alone is not sufficient** to explain this diagnostic. [ADR 0012](../adr/0012-accept-account-owned-ordinary-directories.md) permits it. [ADR 0014](../adr/0014-accept-account-owned-bb-package-file-group-write.md) also permits scoped BB package/runtime-file group write, but not database-file group write or generic root-owned group-writable ancestors. Do not chmod `/Applications`, recursively repair `.bb`, or broaden policy based solely on this log.

Desktop ambiguity and plugin permission refusal are separate checks. A shared underlying layout is possible but not established.

## Recovery and other warnings

- Pi 1.3.0 installation, default configuration, MCP adapter, other Pi packages, final Pi package refresh, managed skills and Homebrew maintenance all report success. They do not clear earlier BB failures.
- BB machine preparation explicitly deferred because existing state/service/overrides were preserved; it did not claim readiness and is not the reported failure.
- Missing optional z.ai and Go credentials, tmux not running, and pending reboot are warnings, not these BB failures.
- Portless installation succeeded after its “Tailscale not found” warning. The earlier log reports the Tailscale GUI app running; [`install_portless_cli`](../../mac.sh#L2396) checks CLI PATH availability, while [`setup_tailscale`](../../mac.sh#L885) checks the cask/app. This is not evidence that Tailscale itself was absent or that tunnel readiness recovered. No tunnel was tested.

## Remote inspection limitation

Trusted local Tailscale inventory identifies online peer **Scott’s MacBook Neo**, macOS, DNS `scotts-macbook-neo.hair-salmon.ts.net`, address `100.113.242.107`. The known repository account `scowalt` was selected for a bounded read-only identity/metadata command.

```text
tailscale ssh scowalt@scotts-macbook-neo.hair-salmon.ts.net <read-only identity/stat commands>
No ED25519 host key is known ... and you have requested strict checking.
Host key verification failed.
```

Exit 255 occurred before remote commands ran. No known-host entry was found for the short name, FQDN or inventory address. Host checking was not weakened and no key was enrolled. Inventory matching does not independently authenticate the collector upload or establish remote filesystem state.

## Contained validation

The initial replay intentionally asserted successful outcomes, went red with both exact diagnostics, and included single-variable controls. This diagnoses refusal behavior; it is **not** a proposed requirement to accept unsafe/ambiguous state. Its two tests ran in 0.031 seconds (runner 0.2 seconds), artifacts `/tmp/setup-fixture-matrix-ifimi4kk`.

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --tool-path /usr/bin:/bin tests/test_neo_diagnosis.py
```

After changing the diagnostic assertions to expect the refusals and adding the ancestor matrix, the same contained runner with `--pwsh /opt/microsoft/powershell/7/pwsh` passed these five sequential entries:

- Temporary diagnostic replay: 3 tests, 0.053 seconds.
- `tests/test_fixture_containment.py`: 9 tests, including actual-source extraction and inherited network denial.
- `tests/setup-default-contract.sh`: 3 scheduling/finalization and 9 environment tests.
- `tests/bb-desktop-contract.sh`: 112 helper and 3 caller tests, plus inert PowerShell wrapper coverage.
- `tests/bb-plugin-refresh-contract.sh`: 78 tests, including refusal reporting, directory/file policy and failure aggregation.

Artifacts: `/tmp/setup-fixture-matrix-phqy3ym0`. Mandatory kernel/FD preflight passed; HOME/stdio were private, external effects mocked, and no live setup/app/plugin execution occurred. Passing tests validate expected policy behavior, **not a fix**, native macOS readiness or recovery of this run. The temporary replay was moved outside the test suite to `/tmp/setup-neo-diagnosis.MhNpU4a1/debug/test_neo_diagnosis.py`; production scripts were unchanged.

## Owner-management implementation evidence

Following the owner's clarification, all six setup entry points remove desktop installer calls, embedded artifact/transaction helpers and Windows's obsolete desktop failure accumulator. They report owner-management without probing either application location. No opt-out is needed and no installed app, fork, link, menu entry or recovery file is removed. BB preparation, Ubuntu server management and plugin-refresh production code remain unchanged. Versions advance to macOS 307, Ubuntu 339, Bazzite 184, Pi 280, WSL 263 and Windows 199.

The replacement contract went red before production edits: inert traps caught desktop calls through the real extracted Bash callers and PowerShell AST-selected caller/logging wrapper. After removal, its four methods pass, covering six source entry points and 148 caller combinations: absent apps, malformed duplicate/fork copies, real/dangling links, work/headless values and independent/plugin failures. State snapshots retain contents, link targets, identity, ownership, modes and timestamps. Real headless gates are separately covered by `headless-contract.sh`; generic gates are mocked in the Bash desktop-state matrix so every ordinary caller can be exercised safely.

- Targeted five-entry contained run: `/tmp/setup-fixture-matrix-5a0yto9j`, all pass.
- Expanded pre-push dispatcher: `/tmp/setup-fixture-matrix-i075i9m8`, first **32 entries pass** before the outer 1,800-second execution timeout interrupted the run. The in-progress package suite was not credited; a subsequent exact-root process check found no remaining fixture processes, and no unrelated processes were signaled.
- Remaining **16 entries pass** in `/tmp/setup-fixture-matrix-r59ko20t`, with a new mandatory preflight, explicit existing Node/PowerShell/mise/Chezmoi/Bun and bounded 900-second suite deadlines. Together the two result files cover all **48 unique dispatcher entries** with status 0; this is not an uninterrupted successful hook invocation.
- Bash syntax, ShellCheck, changed Python syntax, six version increments, document links/whitespace and cached Markdownlint pass. Static linter evidence: `/tmp/bb-desktop-unmanaged-static.Tku3dU3w`, also with kernel denial/private stdio.

Optional installed-code/external-dotfiles probes, native Bash 3.2 and native Windows ACL/handle coverage retain their explicit skips/omissions. Linux PowerShell fixtures are not native Windows/macOS rollout. No live setup, app/plugin execution, permission changes or machine remediation occurred; this change neither diagnoses nor fixes the independent `writable-local-state` failure.

## Next steps

1. Obtain the Mac's SSH host key through a trusted channel, or have the owner provide a metadata-only capture. Do not accept an unauthenticated key just to continue.
2. Desktop installation/update is now owner-managed without setup inventory or duplicate removal. Any owner-directed app consolidation remains separate from this change. For plugin diagnosis, identify only the actual local server/package route through read-only metadata.
3. For the actual local server, inspect ancestor and package/data-file metadata, beginning with `/Applications`, the selected bundle/package route, the actual data directory and its `bb.db`/migration/runtime markers. Do not dump configuration, process environments or credentials.
4. Identify the first rejected object before proposing a scoped policy change or an owner-approved permission correction. A native Applications compatibility change would need separate regression coverage and an explicit decision about its trust boundary.
5. Recheck metadata, then perform any setup/plugin retry only in a separately approved maintenance window. An unchanged-state rerun is not a demonstrated remedy.
