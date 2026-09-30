# TASK-57 execution-boundary audit

Current-source update: [TASK-58 rollback evidence](2026-09-30-setup-rollback.md). The runner, extraction and kernel/FD containment requirements below remain active. The old maintenance preambles/default-policy tests were replaced by ordinary-setup and data-only environment contracts; counts and commands below are historical TASK-57 evidence.

Historical alias: this work was branch-local TASK-56 before the main integration. TASK-57 now tracks it; upstream's unrelated TASK-56 is unchanged. Historical artifact paths remain unchanged.

Status: the integrated-source **40/40-entry** aggregate (`/tmp/setup-fixture-matrix-u3o1b6du`) passes under unchanged kernel containment after the additional upstream audit below. The post-review `/tmp/setup-fixture-matrix-ptafh82r` aggregate is pre-integration evidence; `/tmp/setup-fixture-matrix-vghy85gm` predates the final logging fixes. Explicit skips, the trusted-Markdownlint blocker and criterion dispositions are in [validation evidence](2026-09-29-non-disruptive-validation.md). Parent accepted AC1–9 against the reviewed pre-integration evidence; integrated-source review, AC10 and task completion remain with parent/user. Original [incident uncertainty](2026-09-29-fixture-containment-incident.md) is unchanged.

## Scope and findings

The audit enumerated 58 execution-bearing files reached by the contract matrix: 28 Python, 11 PowerShell, 18 Bash and one Node test file. Other contract entry scripts dispatch to these files or perform static checks. The review concerns source loading, entry-point control, setup-call ordering, external-command replacement, temporary roots and optional native probes; it is not a claim to have re-proven every behavioral assertion.

| Execution surface | Current boundary and repairs |
| --- | --- |
| Nine whole-file Bash loaders | AI-agent, Attention Span, Tea, RPIV, skill ownership, RTK, reliability, managed skills and weekly contracts now load a generated definitions-only tree. Static source checks still inspect the real checkout. No production top-level entry invocation is emitted. |
| Two whole-file PowerShell loaders | Attention Span and reliability now import only `FunctionDefinitionAst` nodes. No regex-erased whole source is evaluated. |
| Other PowerShell helper imports | Desktop, Backlog, model defaults, runtime, Telegram and upload fixtures select function ASTs or synthetic caller ASTs. Infisical's marker block now requires every statement to be a function AST; its real caller and initializer are selected by AST, not closing-brace regexes. |
| Intentional real caller/wrapper execution | Default scheduling, BB desktop/preparation, Infisical, OpenCode, Paseo preservation and Pi-package fixtures install inert function/command replacements and temporary state before invoking the extracted caller. Maintenance fixtures use the real initializer with an explicit switch, not an open-policy stub. BB's generated Windows caller fixture was corrected to restore the real policy after generic stubs. |
| Real logging wrapper fixtures | Windows upload uses an in-memory HTTP handler; Bash reliability defines `curl` before the explicit wrapper call. Post-review regressions apply a strict trailing-X BSD-style mktemp shim to the actual macOS helper and seed regular/symbolic/hardlinked log candidates in private fixture reservations. Real Windows wrapper/log guards/safe tasks/finalization run only after service/transcript/transport mocks and private roots exist; unsafe-directory/start/task failures verify continuation and original errors. The kernel filter is additional protection, not a replacement for mocks. |
| Python desktop helper import | No longer relies solely on `__name__`: AST selection excludes the entry block, rejects unexpected top-level statements and definition-time decorators/annotations/calls, and allows the existing literal defaults/constants. Native command and fetch mocks are installed before installer functions are called. |
| Bounded executable helper programs | Pi metadata/permissions/retirement, Backlog planners, service trust and Infisical APT programs intentionally execute extracted helper code against synthetic files/metadata. These are not whole setup entry points. Real account/auth paths are not fixture targets. |
| Native tool fixtures | Git/Chezmoi operate on synthetic repositories/configuration/destinations with hooks and inherited Git controls isolated. Native npm fixtures use inert local bundles and fixture prefixes/config. Mise activation uses a disposable configuration/data root; Node/npm are now copied there, not exposed through a writable directory symlink to the real runtime. |
| Optional installed-code/cross-repository probes | The sanitized runner does not inherit enabling variables for real Pi/extension registry loads, installed skill CLI probes, native Go catalog/lock probes, external dotfile sources or installed OpenCode shims. Those are skipped, not counted as covered. |
| Node OpenCode tests | Import the policy library; use temporary artifacts, fake fetch/native probes and injected metadata. The optional installed command shim is not enabled. |

## Upstream integration audit

Before executing the integrated source, reviewed all of `tests/opencode-cli.test.cjs`, `tests/fixtures/opencode-homebrew-proof.py` and `tests/test_opencode_cli_callers.py`, including their changed policy/wrapper dependencies from upstream `4ece5ef` and `e169f8d`. This adds one Python fixture to the original 58-file inventory (59 execution-bearing files); no optional integration was enabled.

- HTTP negotiation tests inject a header-sensitive HTTPS emitter before calling the real fetch/install helpers. Core-entry execution occurs only inside that injected VM with a temporary HOME/PATH and forbidden application execution. No socket or actual download is needed.
- Homebrew proof tests map logical Homebrew, `/etc`, `/proc` and Python-tool metadata into a private temporary tree. Only command quarantine/restore is permitted by the Node filesystem proxy; app probes remain inert. The existing `/usr/bin/python3 -I -S` runs the fixture adapter, not an unmocked host proof. Before evaluating the extracted proof, the adapter replaces NSS enumeration/initgroups, open/lstat/fstat/listdir/ACL access, and refuses path-following stat/process signaling. Race mutations affect only fixture files. Native UID/GID values are scalar fixture inputs, not host membership inventory.
- Bash diagnostic wrappers receive a temporary fake Node; PowerShell receives a fake Node script and inert Get-Command/ACL functions before invocation. Extracted real callers retain the local real-policy maintenance initialization, failure aggregation and finalization tests alongside upstream diagnostics. No whole setup source is evaluated.

These are source-specific audited boundaries, not a general filesystem/process sandbox. The existing sanitized sequential runner, mandatory filter/self-test and FD rules remain unchanged. The integration runs passed 5/5 affected contracts and 40/40 aggregate entries without an observed new refusal or unexpected effect; exact commands, counts and retained artifacts are in the validation report. This is not a syscall-wide effects audit.

## Bash extraction boundary

`tests/extract_setup_fixture.py` is a bounded repo-layout extractor, **not a general shell AST**. It ignores production top-level commands, emits only allowlisted literal initialization, rejects unsupported close/trailing-statement layouts and overlapping function starts, and handles here-documents separately.

Normal `bash -n` alone is insufficient. Each function candidate is parsed independently both as written and with only its claimed outer delimiters exchanged between `{ ... }` and `( ... )`. The reciprocal form supports the existing OpenCode subshell helper with the same boundary checks. A premature actual close then mismatches the alternate delimiter rather than allowing a swallowed top-level command and later function to remain syntactically valid. Independent parsing also prevents an unterminated quote in one candidate from being healed by text copied from another.

Benign regressions for the reported `}; printf ...` boundary drift after all required names, indented/mid-line closes, continuation, quote/heredoc boundaries, changed top-level invocation arguments, and the actual PowerShell fixture importer prefixes passed in the separately approved synthetic retry below. At the synthetic-retry stage, full real-source materialization and the repaired matrix were not yet validated; the later authorized stages now provide that evidence. Unsupported syntax must fail before materialization; no permissive fallback is allowed.

## Reproducible runner

`tests/run-fixture-matrix.py` builds a new environment dictionary **before** executing the compiler or dynamically linked C launcher. It does not inherit preload/audit variables, shell startup controls, credentials, agent overrides, proxy variables or optional integration flags. It creates private HOME/USERPROFILE/XDG/Windows-appdata/temp roots and empty npm configuration files, sets a process-local 077 umask for fixture descendants, isolates Git hooks/config, and explicitly opts out of PowerShell/.NET/tool telemetry. Tests requiring another mask set it explicitly. Additional native tools are selected executable links in a private fixture-only directory, not a broad user PATH.

The C launcher validates/closes descriptors before even argument-error/probe paths, refusing socket-backed standard descriptors without printing onto them. It closes nonstandard inherited descriptors, installs `no_new_privs` and seccomp, and refuses the child on failure. After the approved wiring repair, both compiler and mandatory socket-denial preflight use explicit devnull stdin and exclusively created mode-0600 diagnostic files for stdout/stderr, with the sanitized environment and `close_fds=True`. Actual suites likewise use devnull/private files. The runner passes no extra descriptors and never falls back uncontained. Timeouts terminate only the newly created fixture process group.

This is Linux outbound containment, **not a filesystem/process sandbox**. Temporary state, mocks and code review remain necessary. A fixture that rebuilds its own environment may omit telemetry opt-out variables; inherited kernel socket denial still applies. Native Windows, macOS, ARM and real BB session continuity remain unverified.

## Approved synthetic validation history

Parent approved exactly the following command once, for synthetic extraction/signature-drift and inherited socket-construction assertions only. It was run without broadening the arguments:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh \
  --tool-path /usr/bin:/bin \
  tests/test_fixture_containment.py
```

The command returned **1** after successful C compilation because the mandatory `fixture-no-network --self-test` returned **125**. The runner's self-test inherited harness stdout/stderr; read-only inspection confirmed that those harness descriptors are sockets, which the launcher intentionally rejects before filter installation. Actual suite launches already use devnull/private files, but the preflight launch needs the same explicit descriptor control. No guard was relaxed and no retry was made.

Artifacts: `/tmp/setup-fixture-matrix-j4b37uwv`. Only the compiled launcher and private build-home/empty npm-config/temp paths exist; no suite HOME, test log or results JSON was created. **0/5 declared test methods ran**, including **0/2 PowerShell importer cases**; there is no skip report. Signature/brace-drift and inherited-denial regressions remain unvalidated, not passed.

No production setup entry point, PowerShell test child or destination-bearing request was reached in that first attempt. No unexpected effects were observed in its artifact tree; compiler/runtime file accesses were not syscall-traced. Those failure artifacts remain intact.

### Approved narrow repair and one identical-command retry

Only the runner's compiler/preflight descriptor wiring and controlled failure reporting were repaired; the C safeguards stayed unchanged. Parent then approved the **same command above once**, and it returned **0**. The suite also returned **0**: `Ran 5 tests in 1.101s`, `OK`, zero skips; the runner recorded 1.2 seconds.

Actual coverage: **5 methods; 9 named subcases** comprising 3 entry-invocation variants, 4 brace/continuation variants and **both PowerShell importer cases**. Additional mid-line/group, quote/heredoc and marker-preservation assertions passed. The inherited native socket-denial probe passed without re-installing the filter. Signature/brace-drift and inherited-denial regressions in this suite therefore passed, rather than being skipped or inferred.

Artifacts: `/tmp/setup-fixture-matrix-ms6mpi60`. `compiler.log` is empty; `sandbox-self-test.log` records AF_INET/AF_INET6 denial; `test_fixture_containment.log` records all five passes; `results.json` records suite status 0. Diagnostic/result files are 0600 inside a 0700 root. Only expected build/suite files remain; no pre-mock marker was observed. The launcher is byte-identical to the earlier one (SHA-256 `92229787f2066b07bac951946af14db18fc8425ade632cbecb11c6a48c588bc1`).

No unexpected command/file effects were observed in the output or artifact tree; this was not a syscall-wide effects audit. No production setup entry, optional live integration or destination-bearing request was part of the retry. Original remote receipt/telemetry uncertainty is unchanged. At that point **broader behavioral execution remained paused pending review**, and the historical five failures were unresolved validation obligations. Subsequent explicit approval and passing final results are recorded in the linked validation report; none of these historical artifacts were removed.

## Execution-bearing inventory

### Python (28)

- `test_backlog_mcp_retirement.py`
- `test_backlog_windows_planner.py`
- `test_bb_desktop.py`
- `test_bb_directory_preflight.py`
- `test_bb_dotfiles_umask.py`
- `test_bb_machine_preparation.py`
- `test_bb_preparation_permissions.py`
- `test_bb_service_trust.py`
- `test_codex_profile_isolation.py`
- `test_headless.py`
- `test_homebrew_results.py`
- `test_infisical_apt_retirement.py`
- `test_infisical_callers.py`
- `test_infisical_native_retirement.py`
- `test_macos_clt.py`
- `test_managed_skill_suite.py`
- `test_non_disruptive_setup.py`
- `test_opencode_cli_callers.py`
- `test_opencode_go_wiring.py`
- `test_paseo_non_management.py`
- `test_pi_askclaude.py`
- `test_pi_model_defaults.py`
- `test_pi_opencode_go_setup.py`
- `test_pi_package_maintenance.py`
- `test_pi_profile_permissions.py`
- `test_pi_prose_retirement.py`
- `test_shared_node_convergence.py`
- `test_shared_node_runtime.py`

### PowerShell (11)

- `attention-span-removal-powershell.ps1`
- `backlog-mcp-windows.ps1`
- `bb-desktop-windows-contract.ps1`
- `bb-machine-preparation-powershell.ps1`
- `infisical-retirement-native-windows.ps1`
- `infisical-retirement-windows.ps1`
- `pi-model-defaults-powershell.ps1`
- `setup-reliability-powershell.ps1`
- `shared-node-runtime-powershell.ps1`
- `telegram-alerts-powershell.ps1`
- `windows-log-upload-powershell.ps1`

### Bash (18)

- `ai-coding-agent-contract.sh`
- `attention-span-removal-contract.sh`
- `backlog-mcp-retirement-contract.sh`
- `bb-server-contract.sh`
- `claude-code-installation-contract.sh`
- `gitea-client-installation-contract.sh`
- `infisical-retirement-contract.sh`
- `pi-companion-packages-contract.sh`
- `pi-profile-permissions-contract.sh`
- `pi-prose-contract.sh`
- `pi-rpiv-removal-contract.sh`
- `pi-skill-ownership-contract.sh`
- `rtk-removal-contract.sh`
- `setup-reliability-contract.sh`
- `simple-english-skill-contract.sh`
- `telegram-alerts-contract.sh`
- `weekly-log-audit-regressions.sh`
- `windows-log-upload-contract.sh`

### Node (1)

- `opencode-cli.test.cjs`
