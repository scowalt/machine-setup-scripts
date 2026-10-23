# Linux workstation BB maintenance failure: group-writable package files

Machine identifiers and evidence locations in this public copy are [sanitized](../agents/public-evidence.md); technical findings and limitations are unchanged.

## Disposition

**Confirmed v331 failure mechanism; no live repair performed.** Ubuntu setup v331 refused the existing managed `bb-app@0.46.0` package because its regular files are group-writable. Both reported BB errors reproduce from the captured metadata through the real checks. The historical operation that established those permissions is not identified. The owner subsequently chose the [scoped BB group-write allowance in ADR 0014](../adr/0014-accept-account-owned-bb-package-file-group-write.md), superseding the initial permission-repair recommendation.

Source: [exact authenticated collector log](https://logs.example.invalid/logs/linux-workstation/2026-10-14-15-39-08-814.log), retrieved with HTTP 200. Its local run filename is `2026-10-14-113728.log`. Watcher event: `setup-log-watch:09cfd6ca7b997bca082a8f0984ad80982a85a4e55a4a41a7a3107553666ff979`.

## Evidence and causal chain

| Normalized log lines | Interpretation |
| --- | --- |
| 388–389 | Reviewed private TMPDIR and account-environment-reference preflights passed. They are not this blocker. |
| 391–392 | `npm.previous-target` rejected the previously recorded package before installation or service stopping. |
| 396–397 | Plugin discovery rejected `writable-local-state`; it did not run plugin updates. |
| 403–443 | Independent managed-skill and Pi operations continued successfully. |
| 453 | Setup remained incomplete. Neither BB error recovered. |

The recorded owner is:

```text
/home/operator/.local/share/mise/installs/node/24.18.0/lib/node_modules/bb-app
```

Read-only Tailscale SSH capture found:

| Object | Owner UID:GID | Mode |
| --- | --- | --- |
| Package root and all 75 other captured package directories | 1000:1000 | 0775 |
| `package.json`, `server/dist/index.js`, `server/dist/start-server.js` | 1000:1000 | 0664 |
| `dist/bb-app.js` and native CLI launchers | 1000:1000 | 0775 |
| `~/.config/setup-bb-server/package-owner` | 1000:1000 | 0600 |
| `~/.bb` | 1000:1000 | 0700 |
| `~/.bb/bb.db` | 1000:1000 | 0644 |

All **230 captured regular package files** have group write enabled. They are single-linked and account-owned. The expected `bin/bb-app` command link points into the recorded package. There is no world-writable or foreign-owned directory explanation in this capture. A second capture retained the identities, owners and modes of all 306 package objects and the same main-server PID/selection.

The first failing object is the package manifest:

1. [`bb_package_preflight`](../../ubuntu.sh) validates the recorded owner, then calls `bb_package_owned_target_safe`. Its first regular-file check is `package.json`; `0664 & 0022` is nonzero. That produces `npm.previous-target` before the update transaction starts.
2. The caller retains failure and invokes plugin refresh with `block-default`.
3. [`discover` / `verify_package` / `LocalFiles.inspect`](../../lib/bb-plugin-refresh.py) validate a candidate process's package manifest **before** skipping its default data directory for `block-default`. The same manifest fails the regular-file mask, producing `discovery / writable-local-state`.

Thus the second error is a cascading rejection of the same unsafe package, not evidence of a separate plugin API outage. Fixing only the manifest would merely expose further unsafe package files.

This is not an ordinary-directory policy regression. [ADR 0012](../adr/0012-accept-account-owned-ordinary-directories.md) accepts these account-owned 0775 directories but explicitly preserves regular-file safeguards. The reviewed environment-reference exception in [ADR 0013](../adr/0013-preserve-reviewed-bb-environment-inheritance.md) does not extend to package files.

## Diagnosis loop

Only metadata and selected public package identity/hash fields were captured remotely; no setup helper, installed BB application/module, plugin, provider request or lifecycle operation was executed there. Credential contents were not included. The local replay uses definitions-only existing fixtures, inert file contents, mocked process/API/npm effects, private roots/stdio, sanitized environment and mandatory kernel containment.

The initial readiness assertions went red with the exact logged diagnostics:

```text
SERVER_REPLAY: 1 ERROR: BB server [npm.previous-target]: package path safety could not be verified.
PLUGIN_REPLAY: 1 BB_PLUGIN_REFRESH failed discovery writable-local-state
```

Minimization left a single changed input: `package.json` mode 0644 → 0664. Both checks failed; changing it back cleared both, on two repetitions per check. No credentials, native addons, service changes or actual BB execution are needed for this minimal pattern.

Counterfactual tests against the full capture established:

- Making only fixture directories private **does not** clear `npm.previous-target`.
- Removing only group/world-write bits from the 230 fixture package files clears the real package preflight, without changing any directory mode.
- The same package-file-only change clears plugin discovery's failure under the original `block-default` policy, yielding readiness deferral. This does not establish live plugin readiness or prove subsequent maintenance will succeed.

The diagnosis-only harness was temporarily materialized as `tests/test_linux-workstation_failure_diagnosis.py`, then archived outside the checkout under `/tmp/setup-failure-09cfd6ca.WJ1gOP/debug/`. Its final seven tests assert the original refusal plus the minimized/counterfactual behavior; their passing result is **not a live fix**. Initial red artifacts remain at `/tmp/setup-fixture-matrix-avl5vcze` and `/tmp/setup-fixture-matrix-1qvsvhia`.

Executed final sequential command while that temporary test existed:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/operator/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /opt/microsoft/powershell/7/pwsh --tool-path /usr/bin:/bin \
  tests/test_fixture_containment.py tests/setup-default-contract.sh \
  tests/test_linux-workstation_failure_diagnosis.py tests/bb-server-contract.sh \
  tests/bb-plugin-refresh-contract.sh
```

At `/tmp/setup-fixture-matrix-hqzo0o44`, containment (9 tests), setup-default/environment (3 + 7), and the diagnosis harness (7) completed successfully. The broader BB server contract was interrupted by the outer 240-second execution deadline after its diagnostics (33), directory preflight (10), service preflight (35), and dotfiles-umask (16, with 27 reported optional subcase skips) sections passed. Its remaining shell sections did not complete and are **not claimed passed**. The orphaned private fixture process group was identified by its exact sandbox environment and stopped; no unrelated process was targeted. No containment refusal or unexpected live effect was observed.

Plugin refresh was then run separately through the same audited runner with a 150-second suite deadline: **73 tests passed** in 36.4 seconds, at `/tmp/setup-fixture-matrix-1m63amlp`. No production code changed; the temporary harness was removed from the checkout. These Linux offline results do not establish native rollout, BB workflow usability or continuity.

## Installation provenance: bounded conclusions

The official [0.46.0 metadata](https://registry.npmjs.org/bb-app/0.46.0) and [tarball](https://registry.npmjs.org/bb-app/-/bb-app-0.46.0.tgz) were retrieved; tarball SHA-512 matched registry integrity. All **12 inspected installed core payload files** match the official bytes by SHA-256. Official archive modes are 0644 for the manifest/server files and 0755 for launchers, unlike the installed modes. This is not verification of every dependency or proof against historical modification.

The manifest was created at `2026-10-12 11:41:23 -0400`; its ctime is within a millisecond of creation. Other sampled package files have the same creation window. This does not support a later bulk permission rewrite, but timestamps alone cannot identify the installer/copy operation. Available npm logs contained no BB install record; no matching service-journal signal was recovered for that window. Absence is not proof that an operation did not occur.

The ranked provenance/differential hypotheses were checked after reproduction:

1. **Later permission broadening:** not supported by sampled birth/ctime evidence; not categorically excluded.
2. **npm umask bypassing setup's private install mask:** an isolated native npm probe with an inert offline tarball produced 0600 under process mask 0077 with npm masks 0002 and 0000. With process mask 0002 and npm mask 0000 it produced 0664. A permissive installation/copy path is compatible with the state; setup's shown `umask 077` is not itself an explanation.
3. **Directory-only policy regression:** falsified by the private-directory-only counterfactual.
4. **Independent plugin data/process blocker:** unnecessary to explain these errors; package-file-only correction clears the original discovery refusal in replay.

Live read-only systemd properties showed both managed services active/running since October 12, with `UMask=0002`. The main packaged server is still using the recorded 0.46.0 payload. Service activity is not browser/provider readiness. Also, `bb-app-runtime.json` is 0664; it is not the first failure here but can separately fail stopped-server discovery. No change to service-wide umask is recommended without reviewing unrelated BB runtime behavior.

## Owner-approved implementation

The initial diagnosis proposed verifying/rebuilding the package and restoring its regular-file modes. After reviewing recurring group-write failures, the owner instead approved accepting those modes without permission normalization, limited to BB package files, its verified account-owned Node executable and the stopped-server `bb-app-runtime.json` marker. Database, configuration, migration-marker, credential, service-file, lock and private-TMPDIR rules remain unchanged; world-write, foreign/root-system, type, link and snapshot safeguards remain active.

Ubuntu server preflight and artifact verification/restoration use the new package-file rule. The separate setup-owned preparation prefix also accepts its BB package payload and npm package-lock metadata, while retaining private ownership metadata and all role/enrollment deferrals. The shared plugin-refresh helper opts in only at the approved code/runtime reads; shared preparation and refresh blocks remain identical across all five Bash entry points. Regression tests exercise group-writable native dependency trees through the real installation/configuration/caller seam, read-only preparation preflight/verification, native CLI handoff, stopped-marker deferral and all five ordinary callers, without executing BB or plugins.

Live rollout remains separate: arrange an interruption window for ordinary setup, then verify the saved endpoint and required workflows. No live permission, package, service, configuration or credential repair was performed during diagnosis or implementation. Historical fixture-containment uncertainty remains unchanged.

## Implementation validation

All behavioral runs used the audited, sanitized sequential runner with mandatory kernel/descriptor preflight, private roots/stdio, explicit Node `24.20.0` and PowerShell `/opt/microsoft/powershell/7/pwsh`. This remains outbound containment, not filesystem/process isolation; definitions-only imports, inert effects and temporary state remain necessary.

| Stage | Private artifact root | Disposition |
| --- | --- | --- |
| Original package/refresh regressions | `/tmp/setup-fixture-matrix-0p3org_6` | Expected policy failures before the implementation. |
| Initial focused change | `/tmp/setup-fixture-matrix-imv9ujy8` | Seven focused methods passed; later expanded scope supersedes this alone. |
| Intermediate affected matrix | `/tmp/setup-fixture-matrix-3ud_4pdm` | 16/16 entries passed before the preparation and root-account boundary additions. |
| Preparation regressions | `/tmp/setup-fixture-matrix-_6p2hooz` | Expected refusal of group-writable BB payloads at preflight/verify; private-marker/world-write controls passed. |
| Root-account boundary regression | `/tmp/setup-fixture-matrix-7dgtuczw`, `/tmp/setup-fixture-matrix-hvc0a1js` | First run had a missing fixture directory, not a policy red. Corrected fixture exposed two root-file over-acceptances in the initial implementation; final masks preserve the original root-file restriction. |
| Original full metadata replay and preparation focus | `/tmp/setup-fixture-matrix-xsv0vsom` | Both original gates cleared without mode changes; three preparation methods and containment/default contracts passed. Plugin discovery deferred as required, not a live-readiness claim. |
| Final executable source | `/tmp/setup-fixture-matrix-i9zybijy` | **19/19 entries passed**, 953.6 suite-seconds, no timeout. Includes eight focused BB methods, three preparation methods, both original-capture replays and the affected matrix below. |

The final matrix covers containment/defaults, BB server/refresh/desktop/preparation, reliability, headless/shared runtime, macOS CLT/Homebrew results, pending reboot, weekly, Paseo non-management, AI-agent and directory integration contracts. Five explicit optional skips remain: managed-skill native CLI discovery/snapshot and external-dotfiles rendering, external-dotfiles runtime repair-to-skills, and the Paseo cross-repository source check. No optional installed-code integration was enabled; this is not the complete repository pre-push matrix or native macOS/Windows/ARM/WSL/Bazzite/BB continuity evidence.

Bash syntax, ShellCheck, Python AST parsing, cached Markdownlint, whitespace and refresh embedding checks passed; shared preparation blocks are identical. Final source hashes for the five entries, helper and three portable fixture files remained unchanged throughout validation. Command/source manifests remain in `/tmp/bb-group-write-final-validation-vr0zfrnq/`; temporary focused/capture-dependent drivers are archived outside the checkout in the incident's private `debug/` directory. Portable regressions remain in `tests/test_bb_server_diagnostics.py`, `tests/test_bb_plugin_refresh.py` and `tests/test_bb_machine_preparation.py`.
