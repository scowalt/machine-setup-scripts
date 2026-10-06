# Issue #192: contained non-server discovery validation

Policy: [absence-only default-leaf decision](../adr/0009-limit-bb-group-write-exception-to-negative-discovery.md). Base and integration tip at validation: `966a07af6b9935ea0542048b20e06c313a0a6453`. No live setup, native BB/plugin execution, remote inspection, permission repair or lifecycle operation was used. This is not native recovery or rollout evidence.

## Red → green

Private evidence prefix: `/tmp/issue-192-integration/implementer/`.

| Vertical slice | Red fixture root | Green fixture root |
| --- | --- | --- |
| HOME 0750, default `.bb` and enrollment 0775, inert machine daemon, no main evidence: expected `absent`, observed `discovery / writable-local-state` | `setup-fixture-matrix-uzemf1pf` | `setup-fixture-matrix-tj5qwgh0` |
| Partial native evidence without a database must not be `absent` | `setup-fixture-matrix-1x2mcofj` | `setup-fixture-matrix-o81hjb82` |
| Ambiguous/relative main-process claims must not become negative discovery | `setup-fixture-matrix-1btd9m6i` | `setup-fixture-matrix-dpcjtimj` |

Initial fixture corrections are retained, not counted as behavioral red evidence: `setup-fixture-matrix-atywwjl9` exposed fixture umask/string assumptions; `setup-fixture-matrix-3pm2t0st` exposed an earlier-error stub placed only in Ubuntu's preparation branch. Corrected fixtures explicitly set synthetic modes and inject an independent failure in both lifecycle branches.

## Initial-source results (before review correction)

These results cover the first implementation, committed as `d144c0a2ce86b22b02dd0fb79de398746a1b3e2a`. They did not cover ordinary live database volatility; the correction and its separate evidence follow below.

- **64 refresh methods pass, zero skips**: `setup-fixture-matrix-7yk3bpsu` under the private prefix. Coverage includes captured-state controls, strict refusals, all seven evidence names/forms, no-follow metadata errors, candidate/ancestor/marker races, handle cleanup, HOME normalization, mixed roles and real wrapper/caller/log outcomes.
- **42/42 complete pre-push entries pass**: `/tmp/setup-fixture-matrix-0aw6xn_d`. This includes setup-default/environment, extraction/containment, hook dispatch, BB preparation/desktop/server, reliability, headless, shared runtime, CLT/Homebrew, reboot, weekly and orchestration contracts.
- Every run used the audited sanitized sequential runner, private roots/stdio and successful mandatory kernel filter/self-test. No containment failure or unexpected real effect was observed; this was not a syscall-wide effects audit.
- Bash syntax, ShellCheck, changed Python AST parsing, all three embedding checks, whitespace, full comment policy and staged redacted Gitleaks pass. Existing pinned comment-parser packages were invoked directly; no dependency resolution/download was used. Trusted Markdownlint was unavailable; changed Markdown was manually checked.

Exact initial-source commands:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /opt/microsoft/powershell/7/pwsh --tool-path /usr/bin:/bin \
  --artifact-parent /tmp/issue-192-integration/implementer tests/test_bb_plugin_refresh.py

env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tools/run-pre-push-contracts.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /opt/microsoft/powershell/7/pwsh \
  --mise /home/scowalt/.local/bin/mise --chezmoi /home/scowalt/.local/bin/chezmoi \
  --bun /home/scowalt/.bun/bin/bun
```

The private handoff retains exact per-suite results/skips, raw red/green logs, static commands/results and source hashes. Optional installed skills/Pi/extension/Go-lock/OpenCode-shim and cross-repository dotfiles integrations remain disabled. Bash 3.2 and native Windows handle/ACL fixtures are explicit skips. Linux PowerShell coverage does not establish Windows or PowerShell 5.1 behavior; native macOS/WSL/ARM/Bazzite and BB/plugin continuity remain unverified. The earlier [fixture incident's uncertainty](2026-09-29-fixture-containment-incident.md) is unchanged.

Download-capable commit hooks are replaced only for implementation commits with command-local `LEFTHOOK=0`, after the available checks recorded here; persistent hook configuration is unchanged. No push, PR, issue closure or worker dispatch is part of this implementation.

## Review correction: preserve volatile server evidence

Both review axes found that the absence probe also imposed full database/sidecar and directory timestamp stability on already verified live servers. The correction revalidates known live directories through the existing strict identity/permission checks before skipping negative classification. Other positive candidates retain metadata identity, ownership, mode, link-count and presence checks, but not database content/mtime or directory timestamp immutability. Full leaf snapshot stability still gates every accepted negative result. Header, partial-state, process/peer ownership and all negative race/error safeguards remain exercised.

Evidence prefix: `/tmp/issue-192-integration/review-fix/`.

| Stage | Artifact root | Result |
| --- | --- | --- |
| Live database/WAL/SHM/directory activity regression against `d144c0a` | `setup-fixture-matrix-z4kvp1mi` | Four expected red subcases: `discovery / changed-local-state` instead of refresh |
| Strict known-live revalidation before negative probing | `setup-fixture-matrix-v1yl5_eb` | 65 methods pass |
| Remaining positive-candidate volatility regression | `setup-fixture-matrix-tj6dxbh1` | Five expected red subcases, including directory change between stat and open |
| Positive identity-only metadata comparison; full negative snapshot retained | `setup-fixture-matrix-h51w12pk` | 66 methods pass |
| Final-source targeted suite, including additional strict/refusal guards | `setup-fixture-matrix-59r4rpw9` | **69 methods pass, zero skips** |
| Complete final-source inventory, first attempt | `/tmp/setup-fixture-matrix-hioy9oug` | **41/42 pass**; Backlog MCP retirement reports `boundary-changed` |
| Unchanged Backlog contract alone | `setup-fixture-matrix-aet738h6` | Pass, including available PowerShell coverage; native Windows omission retained |
| Complete final-source inventory, recheck | `/tmp/setup-fixture-matrix-cmrfjgxm` | **41/42 pass**; same Backlog refusal at a different fixture case |

The complete inventory is **not an aggregate pass**. The Backlog fixture and all six embedded Backlog helpers are byte-identical to the base; its boundary comparison includes ancestor size/mtime/ctime. The specific changed boundary and cause were not captured, so neither environmental interference nor a resolved flake is claimed. No unrelated policy or fixture was changed to hide this gap. All other entries, including the required affected matrix, pass on both final-source attempts.

Commands use the exact prefixes above with the targeted runner's artifact parent changed to `/tmp/issue-192-integration/review-fix`; the isolated recheck selects `tests/backlog-mcp-retirement-contract.sh`. Final manifests, exact commands, per-entry results/skips and raw logs are retained under that prefix. Bash syntax, ShellCheck, Python AST parsing, all embeddings, staged whitespace/comment policy and redacted Gitleaks pass; trusted Markdownlint remains unavailable. Existing tools only, sequential containment and successful mandatory preflights were retained. No containment failure or unexpected real effect was observed; native recovery and the original incident uncertainty remain unverified.
