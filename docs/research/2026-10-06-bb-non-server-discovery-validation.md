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

## Final-source results

- **64 refresh methods pass, zero skips**: `setup-fixture-matrix-7yk3bpsu` under the private prefix. Coverage includes captured-state controls, strict refusals, all seven evidence names/forms, no-follow metadata errors, candidate/ancestor/marker races, handle cleanup, HOME normalization, mixed roles and real wrapper/caller/log outcomes.
- **42/42 complete pre-push entries pass**: `/tmp/setup-fixture-matrix-0aw6xn_d`. This includes setup-default/environment, extraction/containment, hook dispatch, BB preparation/desktop/server, reliability, headless, shared runtime, CLT/Homebrew, reboot, weekly and orchestration contracts.
- Every run used the audited sanitized sequential runner, private roots/stdio and successful mandatory kernel filter/self-test. No containment failure or unexpected real effect was observed; this was not a syscall-wide effects audit.
- Bash syntax, ShellCheck, changed Python AST parsing, all three embedding checks, whitespace, full comment policy and staged redacted Gitleaks pass. Existing pinned comment-parser packages were invoked directly; no dependency resolution/download was used. Trusted Markdownlint was unavailable; changed Markdown was manually checked.

Exact final commands:

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

Download-capable commit hooks are replaced only for this commit with command-local `LEFTHOOK=0`, after equivalent available checks above; persistent hook configuration is unchanged. No push, PR, issue closure or worker dispatch is part of this implementation.
