# Existing file group write — verification change

[ADR 0018](../adr/0018-accept-existing-file-group-write.md) records the owner's repository-wide decision after Beelink's Visual Explainer installation returned success but post-install verification rejected an account-owned `0664` `.git/config`. Group write alone now passes Unix file verification; no machine permission repair or live setup is part of this change.

## Gate inventory

| File verification family | Change and retained boundaries |
| --- | --- |
| Visual Explainer `regular` | Accept group write on settings, Git metadata, manifests, payload, dependencies and verified legacy copies. Preserve content comparison, ownership, bounded reads, links and snapshots. |
| OpenCode `safePath` / `brewPermissions` | Accept group write on commands, wrappers, metadata and Homebrew regular files, including already-allowed root ownership. Check non-leaf directory type independently of permission bits. Preserve official bytes, root/system directories, pins, command-only migration and recovery. |
| Impeccable `owned` | Apply the same regular-file rule in preflight, promotion, removal and disposal, including staged engines/cache files. Stage/profile directories and Windows ACLs remain private. |
| Pi Go `regular` | Remove only group write from the file rejection mask, including direct credential inputs. Independent group/world readability and private profile requirements remain. Updated credentials are still newly written privately; unchanged accepted credentials retain their mode. |
| Backlog retirement / TOML parser | Accept group write on mutable metadata and recognized parser executables. Keep metadata snapshots, parser identity, linked-ancestor and foreign/world-write refusals. |
| BB Pi trust adapter CLI | Accept group write before the existing native health command. Keep explicit CLI, account, resource and workspace/MCP approval checks. |
| BB plugin refresh `LocalFiles` | Remove package-specific group-write switches; apply the regular-file rule to package, data and metadata files. Keep directory, process/peer identity, native CLI selection, readiness and changed-evidence checks. |
| BB preparation | Accept group write on markers and read-only service files without invoking the former group-privacy proof. Preserve directory/alias policy, single-link service reads, stable reference/listing snapshots, role detection and the separate prefix. |
| Ubuntu BB server | Accept file group write in owned metadata, native artifact validation, unit/drop-in/source snapshots, identity/endpoint guards and native config locks. Preserve independent confidentiality, exact supported content, loaded selection, ownership, readiness and restoration. |
| macOS completion protection | Preserve file group write instead of removing it to satisfy completion checks; retain world-write protection and existing privileged-directory rules. |

All six standalone entry points carry the shared changes and incremented versions. Native Windows ACL policy, ordinary/private directory boundaries, private file creation, ownership, world-write, type/link, content and snapshot rules remain independent. An accepted mode transition during verification is still a changed snapshot, not cached trust.

## Regression and validation

The new real-wrapper Visual Explainer regression was run before the fix: all six wrappers failed with the exact `failed:unsafe-file` warning after a native local Git clone under umask `0002`. The minimized mode-only test also failed. Existing `0664` checkouts, repeat installation and general refresh are covered without chmod workarounds.

Other updated fixtures cover group-writable OpenCode commands/receipts, Impeccable managed/staged files, Backlog metadata/parser, BB metadata/services/locks, adapter CLI and credential write-only group access. World-writable negative controls, links, foreign ownership and metadata races remain failures. Tests that previously used group write to force a generic failure now use world write; their continuation/finalization assertions remain.

Behavioral execution uses the audited sanitized runner, mandatory kernel/FD preflight, private roots and sequential suites. All external effects are inert, native runtimes are copied where required, and no live app, extension, skill, service, provider or installer is used. Native Windows/macOS/ARM/WSL/Bazzite rollout and optional installed-code integrations remain separate evidence.

All **48 contract entries** have passing evidence after targeted reruns. The initial full dispatcher at `/tmp/setup-fixture-matrix-ema51046` passed 43/48; five entries retained old group-write failure expectations or exposed regression-fixture issues. OpenCode's file-ancestor control also exposed a type check that had depended on the old permission refusal; it now rejects non-directory ancestors independently. The sequential rerun at `/tmp/setup-fixture-matrix-hqym10la` passed Backlog, plugin refresh, OpenCode, Go and final preparation. Its expanded BB metadata fixture initially used group-readable credential metadata, exercising an independent confidentiality refusal; correcting it to write-only group access produced the complete BB server pass at `/tmp/setup-fixture-matrix-bkpyhtha` (290.8 seconds). No failure or optional skip was counted as a pass, and the original failure artifacts remain retained.

The original full-dispatch command was:

```sh
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tools/run-pre-push-contracts.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /opt/microsoft/powershell/7/pwsh \
  --mise /home/scowalt/.local/bin/mise \
  --chezmoi /home/scowalt/.local/bin/chezmoi \
  --bun /home/scowalt/.bun/bin/bun
```

Before publication, remote main advanced to `83345e6` with the generated bb ingress watchdog. Integration preserves its strict startup, identity checks, transient-failure tolerance and no-op regeneration while applying the file policy to the new identity-file check and unchanged `0720` guards. Ubuntu advances to version 342. The contained default, extraction/containment and expanded 29-method watchdog suites passed at `/tmp/setup-fixture-matrix-qb5s8rv2`; the earlier pre-push attempt was cancelled before publishing so that the integrated source could be validated instead.

Reruns used `tests/run-fixture-matrix.py` with the same Node/PowerShell, explicit native tool selectors, a 900-second per-suite deadline and fresh private roots; suites never ran concurrently. The new Visual Explainer regression passed all 16 methods, including six-wrapper native-mode installation/repeat/refresh. OpenCode passed 430/431 cases with one optional installed-shim skip. ShellCheck on every modified Bash file, Bash/Python/Node syntax, all six embedding checks and whitespace checks pass. Original-red evidence is at `/tmp/setup-fixture-matrix-p7tf9929`; command/result records and source hashes are retained privately at `/tmp/setup-file-group-write.ji8KDc`.
