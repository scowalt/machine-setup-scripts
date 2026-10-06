# Darwin BB discovery: oversized process-argument buffer

## Native evidence and scope

The `scott-macbook-m3` macOS setup v273 log reported `discovery / process-proof-unavailable` at lines 123–124 ([collector upload](https://logs.scowalt.com/logs/scott-macbook-m3/2026-10-05-13-21-05-553.log); authenticated access required).

User-run read-only probes established current-state evidence without running setup, BB or plugin operations:

- Account UID 501; a 1,202-row ASCII UID/PID table returned status 0, no stderr and no rejected rows. A separate UID/start-time sample passed the actual helper parser in a contained replay.
- Inspection encountered PID 613 with `KERN_PROCARGS2` return -1, errno 22 (`EINVAL`). The PID remained present with the same UID/start text afterward. Neither its arguments nor environment were printed or saved.
- A one-variable self-process control then measured:

```text
kern.argmax= 1048576
buffer_bytes= 2097152 return= -1 errno= 22
buffer_bytes= 1048576 return= 0 errno= 0
```

This confirms an oversized-query defect, not a need to weaken process ownership checks. The helper requested a fixed 2 MiB. Apple's [`sysctl_procargsx`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sysctl.c) reserves the argument-count word, then rejects a buffer larger than `ARG_MAX` before looking up the PID. The inspected upstream source is not an attestation of the Mac's kernel build; the native same-process comparison independently establishes the sizing behavior.

The captures do not reconstruct the earlier setup's entire process table or prove downstream BB identity, API compatibility, plugin refresh, or workload continuity. PID 613's role remains unknown. Synthetic fixture argv, packages and API responses are not additional Mac evidence.

## Repair and regression

[`Processes.read()`](../../lib/bb-plugin-refresh.py) now reads `kern.argmax` through the existing native library after the UID/start guard. It requires a successful integer-sized response, enough room for the argument-count word, and the existing 8 MiB policy ceiling before allocation. The process query uses that validated limit and rejects a returned length outside its buffer. Native failures, including `EINVAL`, remain fatal; there is no guessed-size fallback, skipped unknown process, permission repair, new lifecycle operation or Linux policy change.

The shared helper is regenerated in all five Bash entry points. Existing UID/start parsing, package/data trust, accepted-peer proof, native-version restrictions, disabled/pinned/source preservation, stopped/safe-mode deferrals and final failure aggregation remain in force.

[`tests/test_bb_plugin_refresh.py`](../../tests/test_bb_plugin_refresh.py) now models the kernel's request-size rejection instead of unconditionally accepting a 2 MiB buffer. Five added methods cover captured and alternate limits, verified synthetic refresh/revalidation, invalid limit status/width/range before allocation, native-query errors and out-of-buffer results. Existing Darwin success and security-boundary cases also use the corrected native model.

## Validation

All behavioral execution used the [audited runner](2026-09-29-fixture-execution-audit.md), mandatory kernel filter/self-test, sanitized environment, private roots/stdio, preinstalled mocks and sequential suites. The [incident's uncertainty](2026-09-29-fixture-containment-incident.md) is unchanged.

| Stage | Artifacts | Result |
| --- | --- | --- |
| Reduced syscall-result replay | `/tmp/setup-fixture-matrix-o3_8isk2` | Exact discovery refusal twice in 0.2s; synthetic successful-query control passes. |
| Regression before production edit | `/tmp/setup-fixture-matrix-y6294zok` | Red: 52 methods, 125 failures and 12 errors. The captured 1 MiB case fails at the real syscall guard; modeled successful discovery reports the logged failure instead. |
| Same targeted suite after repair | `/tmp/setup-fixture-matrix-qr7mkjak` | 52 methods pass, zero skips, 9.3s. |
| Final affected matrix | `/tmp/setup-fixture-matrix-6n8hsmd5` | 17/17 entries pass, including 52 refresh methods and the prior OpenCode fix. |

Targeted red/green command:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh \
  --tool-path /usr/bin:/bin --timeout 180 tests/test_bb_plugin_refresh.py
```

Final matrix command:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh \
  --tool-path /tmp/opencode-item1-tools-8V2YfE:/usr/bin:/bin --timeout 300 \
  tests/test_fixture_containment.py tests/setup-default-contract.sh \
  tests/test_bb_plugin_refresh.py tests/bb-desktop-contract.sh \
  tests/bb-machine-preparation-contract.sh tests/bb-server-contract.sh \
  tests/setup-reliability-contract.sh tests/headless-contract.sh \
  tests/shared-node-runtime-contract.sh tests/test_macos_clt.py \
  tests/test_homebrew_results.py tests/pending-reboot-contract.sh \
  tests/weekly-log-audit-regressions.sh tests/paseo-non-management-contract.sh \
  tests/ai-coding-agent-contract.sh tests/opencode-cli-contract.sh \
  tests/bash-compatibility-contract.sh
```

The private extra tool directory contains only selected links to existing ELF-native mise, Chezmoi and Bun executables; none was installed. Bash syntax, ShellCheck, Python AST parsing, BB/OpenCode embedding consistency and whitespace checks pass. Temporary probes/replays were archived outside the checkout; no production debug instrumentation remains.

Explicit skips: Bash 3.2, external runtime/Paseo/managed-skills dotfiles, installed managed-skills CLI probes and the optional OpenCode command shim. Linux-hosted PowerShell fixtures ran; native Windows/ACLs, full macOS setup/plugin operation and other platform rollout remain unverified. Markdownlint was not run. No live setup, BB/plugin execution, permission changes, commit, push or deployment was part of this repair.
