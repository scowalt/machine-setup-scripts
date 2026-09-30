# TASK-57 fixture-containment incident

Historical alias: the incident occurred while this work was branch-local TASK-56. It is now TASK-57 following a CLI-managed collision resolution with upstream's unrelated TASK-56. Original artifact names, incident facts and chronology are unchanged; publication permission does not resolve the incident exception.

Status: parent subsequently approved staged contained validation; the refreshed post-review aggregate at `/tmp/setup-fixture-matrix-ptafh82r` and later upstream-integration aggregate at `/tmp/setup-fixture-matrix-u3o1b6du` each passed 40/40 entries on their respective source revisions. See [the later validation evidence, skips and blockers](2026-09-29-non-disruptive-validation.md). Original incident facts, remote receipt/retention uncertainty and possible additional telemetry remain unchanged. The failed preflight, approved repair/retry and capability evidence are preserved chronologically below. Passing later tests is neither native rollout evidence nor an unqualified pass for the task's no-live-effects clause.

## Observed incident

During the sequential contract run, `tests/attention-span-removal-powershell.ps1` evaluated the whole Windows setup source after removing only the former bare `Initialize-WindowsEnvironment` invocation. The newly parameterized invocation no longer matched that removal. It reached the ordinary setup wrapper before the fixture installed its mocks.

Known outbound activity: **three real multipart POST attempts** to `https://logs.scowalt.com/upload`, with the machine hostname as a query parameter. All reported HTTP 500. This does **not** establish that the collector received or retained nothing. No collector investigation, remote deletion, or further request is authorized or has been made during containment.

The attempted file payload was the same closed 2,529-byte PowerShell transcript on each retry. Its SHA-256 is `7ff7e2025d2af830d151dbc2172346cc4ec3582de294f5a467d1398a73a10ce4`. The sidecar records `pending`, `attempts: 3`, and `statusCode: 500`. Original artifacts are retained privately under `/tmp/task56-contracts-sequential-pj35yfk5/attention-span-removal-contract-home`; they are not copied into this repository or uploaded for diagnosis.

The transcript contains ordinary PowerShell account, machine, process, runtime/version and host-application metadata, deferred-operation descriptions, a failed service inspection, creation of an empty fixture `Code` directory, and reboot wording. The inspected transcript has no API-key, password or Authorization labels. Its token/credential words occur in static deferral descriptions. This is a bounded content inspection, **not proof that arbitrary secrets could not occur in an untraced process**.

### Environment and observed effects

The runner used an explicit new environment dictionary, not an inherited environment copy:

| Surface | Effective selection |
| --- | --- |
| `HOME`, `USERPROFILE` | The same newly created, private suite-specific temporary home |
| XDG config, data, cache | Subdirectories of that temporary home |
| Agent overrides | No inherited Claude, Codex, Pi or other agent-profile overrides |
| Credentials | No inherited token, key, password, authorization or proxy variables |
| Git | No system/global configuration; hooks redirected to `/dev/null` |
| Executables | Explicit existing Node/PowerShell runtime paths and system/tool directories; not a filesystem sandbox |
| PowerShell profile | `-NoProfile`; **telemetry opt-out was not set in the incident runner** |

Observed files are the transcript, its upload sidecar, and PowerShell startup/telemetry cache files, all under that temporary home. Observed directories also include the empty fixture `Code` directory.

The selected source path was `Initialize-SetupPolicy` (no maintenance argument), log preparation, `Invoke-SetupSafeTasks`, policy completion, and log finalization. The transcript corroborates the safe-path deferrals. That path attempts only environment-file reads, named service observations, `Code` creation, pending-reboot registry reads, and logging/upload; it does not call package installers, service lifecycle operations, credential writes, dotfile application, apps, skills or extensions. The suite home contained no environment or agent credential files.

**Limits:** no syscall trace or pre-run machine-wide snapshot was captured. Absence of package/service/credential mutation is supported by the selected source path and observed artifacts, not by temporary HOME alone. Incidental runtime/configuration/certificate reads cannot be retrospectively enumerated. PowerShell created a telemetry identifier; extra runtime network attempts cannot be excluded from the available evidence. The three uploads are the known requests, not a proven upper bound on all outbound activity. Remote receipt/retention remains unknown.

## Containment capabilities

Parent approved only namespace checks with inert children and socket-construction tests without destinations, DNS, connect, bind, listeners or packet transmission. Behavioral suites remain paused.

| Command or check | Result |
| --- | --- |
| `unshare --user --map-root-user --net -- /bin/true` | Exit 1: writing `uid_map` was not permitted; child did not run |
| `bwrap --unshare-user --unshare-net --ro-bind / / --dev /dev --proc /proc -- /bin/true` | Exit 1: private loopback setup was not permitted; child did not run |
| `/usr/bin/cc -O2 -Wall -Wextra -Werror tests/fixture-no-network.c -o <private-temp>/fixture-no-network` | Exit 0; no installation/dependency changes |
| `<sandbox> --self-test` | Exit 0: native AF_INET and AF_INET6 socket creation both denied with EPERM |
| `<sandbox> -- /bin/true` | Exit 0 |
| Python under sandbox: AF_INET/AF_INET6 socket constructors only | Exit 0: both denied with EPERM |
| Node under sandbox spawning native `--assert-inherited-denial` | Exit 0: descendant denied without installing its own filter |
| PowerShell/.NET under sandbox: IPv4/IPv6 `Socket` constructors only | Exit 0: both report `SocketError.AccessDenied` |
| PowerShell under sandbox spawning native inherited-denial probe | Exit 0 |
| Explicitly inherited nonstandard pipe descriptor | Closed before child execution; Python receives EBADF |
| Invalid launcher argument | Exit 125, no child |
| Inert fault-injected zero-length seccomp filter | Kernel refusal; launcher exits 125 without executing the marker child |

The initial .NET assertion expected native errno 1; .NET maps the denial to native error 13 / `AccessDenied`. Bounded exception-type/code inspection established this mapping, and the corrected assertion passed. No destination was supplied in either attempt.

Capability artifacts are retained privately at `/tmp/task56-containment-i28c144a`. They contain self-test results, not the incident transcript.

The FD-hardened v2 launcher was compiled and the approved local-only capability checks repeated. Descriptor validation now precedes even argument/probe errors, and unsafe standard descriptors are closed without writing a diagnostic to them. Node's default captured-child stdio uses local socket pairs: the stricter probe correctly refused those descriptors with 125. Read-only `fstat` inspection established that all three were socket-backed. Repeating the Node inherited-filter probe with explicitly inherited pipe stdio passed. Native, Python and PowerShell descendant denial, .NET constructor denial, nonstandard FD closure, and invalid-filter refusal passed again. No destination was used; behavioral suites remained paused.

### What the seccomp launcher proves

`tests/fixture-no-network.c` installs a Linux kernel filter before executing a fixture. It closes all descriptors numbered 3 or higher, rejects socket-backed standard descriptors, sets `no_new_privs`, and refuses to execute if descriptor validation or filter installation fails. The filter is inherited by threads, forks and exec descendants. It denies socket creation and network-operation syscalls regardless of language or PATH mocks. It also denies io_uring network bypasses, cross-process FD acquisition and namespace switching, and rejects non-native syscall architectures.

The launcher does not rely on a newly created network namespace. Tests do not claim that socket-creation denial by itself protects pre-existing sockets: descriptor closure/rejection is a separate prerequisite. No pre-existing Internet socket was created for testing. Standard-socket rejection is source-inspected; nonstandard descriptor closure was exercised with an inert pipe.

**Remaining boundaries:** this is not a filesystem, process, or hostile-code sandbox. It cannot substitute for temporary roots, credential-free environments, function/AST extraction, inert external commands, or careful native-tool fixture contracts. Ordinary file writes and non-network process operations still require those controls. Unsupported platforms/architectures or failed filter installation must stop, never fall back to an uncontained run.

## First approved synthetic-suite attempt

The exact parent-approved command was run once:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh --tool-path /usr/bin:/bin tests/test_fixture_containment.py
```

**Result:** outer command exit 1 (`CalledProcessError`); C compilation completed, but `<artifact-root>/fixture-no-network --self-test` returned 125. Execution stopped before creating a suite HOME, suite log or results JSON. No fallback, retry or other suite was run.

**Counts:** zero of five declared test methods executed. The PowerShell regression's two importer cases both remain unrun; no skip result was produced. Signature/brace/quote/heredoc drift and inherited-denial regressions have **not passed or failed behaviorally**, because the suite never started.

**Local evidence:** `/tmp/setup-fixture-matrix-j4b37uwv` is mode 0700 and contains only the compiled launcher plus a private `build-home`, empty `.npmrc`/`global.npmrc` files and empty `tmp` directory. The launcher is 16,592 bytes, SHA-256 `92229787f2066b07bac951946af14db18fc8425ade632cbecb11c6a48c588bc1`. No unexpected file effects were observed in this artifact tree. There is no syscall-level proof of every compiler/runtime file access.

**Preflight issue:** the runner supplies controlled files/devnull when launching actual suites, but its earlier mandatory self-test inherits its caller's standard descriptors. Read-only inspection of the current tool harness shows stdout and stderr are socket-backed. The C launcher's deliberate standard-socket rejection occurs before filter installation and returns 125 without writing a diagnostic onto those sockets. This explains the fail-closed stop; it is not evidence that the kernel filter became unavailable. A future repair should give the self-test explicit devnull/file or pipe descriptors, without weakening rejection. No repair or rerun was performed during that first attempt. The separately approved repair and retry are recorded below.

No production setup entry point or PowerShell test child was reached. No destination-bearing request was part of this command. The original collector-receipt and telemetry uncertainty above remains unchanged.

## Separately approved stdio repair and synthetic retry

Parent subsequently approved changing only `tests/run-fixture-matrix.py` so both compilation and mandatory sandbox verification receive explicit non-socket stdio. Each stage now receives stdin from `/dev/null`, stdout/stderr through its own diagnostic file created exclusively with mode 0600 before launch, `close_fds=True`, and the same sanitized environment. Launch, timeout and nonzero-stage failures remain controlled nonzero refusals. No C socket/FD/filter guard changed.

The **same exact command shown above** was run once after that repair. **Outer exit: 0; suite exit: 0.** Runner duration was 1.2 seconds; unittest reported five methods in 1.101 seconds, `OK`, with zero skips.

Coverage actually executed:

- Three named Bash entry-invocation subcases passed without executing top-level marker code.
- Four named closing-brace/trailing-statement subcases plus the additional mid-line/group-close case were rejected as intended.
- Quoted-brace, complete-heredoc and missing-heredoc-delimiter assertions passed.
- Both actual PowerShell importer-prefix subcases passed against synthetic changed-signature scripts: Attention Span and setup reliability. No pre-mock marker was created. This is Linux PowerShell coverage, not native Windows verification.
- The native descendant probe passed AF_INET/AF_INET6 socket-creation denial without installing its own filter or supplying any destination.

These are **5 methods and 9 named unittest subcases** (3 entry, 4 brace, 2 PowerShell), not fourteen separately reported methods. All signature/brace-drift and inherited-denial regressions in this synthetic suite passed.

Artifacts are retained at `/tmp/setup-fixture-matrix-ms6mpi60` (0700): `compiler.log` (empty), `sandbox-self-test.log` (explicit socket-denial PASS), `test_fixture_containment.log`, and `results.json` (suite status 0). All four diagnostic/result files are mode 0600. Build/suite homes contain the expected empty npm configuration and temp directories; synthetic temporary directories were cleaned up and no `before-mocks` marker remains. No unexpected command/file effects were observed in the recorded output or artifact tree; there was no syscall-wide effects trace.

The compiled launcher is byte-identical to the earlier failed-preflight artifact, retaining SHA-256 `92229787f2066b07bac951946af14db18fc8425ade632cbecb11c6a48c588bc1`. The successful result therefore did not come from weakening or replacing its guards. The earlier `/tmp/setup-fixture-matrix-j4b37uwv` failure artifacts remain intact.

No production setup entry point, optional live integration or destination-bearing request was part of this retry. At this stage broader behavioral suites remained paused pending parent review. Original collector receipt/retention and telemetry uncertainty is unchanged.

## Fixture audit and repair status

The execution-bearing audit index covers 58 files. Whole-file evaluation was found in nine Bash contract scripts and two PowerShell fixtures (the initial quick count of ten Bash scripts included a bounded function extractor).

- PowerShell Attention Span and reliability fixtures now import only parsed top-level function AST nodes, never a source string with an entry-line regex removed.
- Nine Bash contracts now obtain a separately materialized definitions-only source tree through `tests/extract_setup_fixture.py`, while their static checks remain in the real repository. Production top-level statements and invocations are not emitted. Existing source/strip expressions operate on that definitions-only tree, not production entry points.
- The current execution boundaries in all 58 indexed files have been reviewed and documented separately in [the execution audit](2026-09-29-fixture-execution-audit.md), including intentional caller/wrapper execution, native fixture inputs and optional installed-code controls. Infisical AST loading, desktop helper import and writable native-runtime symlinks received additional repairs.
- Synthetic definitions-only extraction, changed-entry-signature and inherited-denial regressions passed as recorded above. At that stage, materializing the full real Bash sources and rerunning the repaired contract matrix remained unvalidated.
- The sanitized runner first failed closed on inherited standard descriptors; the separately approved descriptor-wiring repair and single retry passed. Execution was then held for review; no broader suite followed until parent explicitly authorized staged resumption.

The earlier 31/36 result is historical diagnostic information only. Remaining failing suites at that point were Attention Span removal, Backlog MCP retirement, BB machine preparation, Infisical retirement and setup reliability. Their source/fixture repairs were unvalidated at that point. No task acceptance criteria were marked complete on the basis of that count.

## Subsequent authorized validation

Parent lifted the blanket pause for staged, audited offline execution only. Actual-source extraction, the initial cohort and all five historical failures now have contained passing evidence; the final aggregate returned 40/40 entries passing. A failed fixture HOME precondition led to a stricter runner umask, and shared-directory/path-sentinel fixtures were repaired without weakening production checks. The C filter, descriptor rejection/closure and refusal behavior remained unchanged. The [validation report](2026-09-29-non-disruptive-validation.md) records exact commands, every stage, skips, native omissions and static checks.

No new containment incident or unexpected real effect was observed in those stages; they were not syscall-wide effects audits. The original private incident artifacts, failed-preflight artifacts and all subsequent test roots remain retained. No collector follow-up request or remote cleanup was made. Three original uploads remain known requests, not proof of nonreceipt/nonretention or an upper bound on telemetry. TASK-57 remains In Progress, and AC10's no-live-effects clause is explicitly not claimed as an unqualified pass.

A later parent source review found BSD log-template portability and Windows logger-failure continuation gaps despite the earlier passing aggregate. Contained red regressions reproduced the relevant paths; affected contracts and a refreshed 40/40 aggregate passed after the logging fixes. The earlier `/tmp/setup-fixture-matrix-vghy85gm` result is explicitly pre-fix evidence, and the corresponding post-review, pre-integration root is `/tmp/setup-fixture-matrix-ptafh82r`. The [validation report](2026-09-29-non-disruptive-validation.md) distinguishes both revisions and preserves their artifacts. These simulated BSD and Linux PowerShell fixtures neither exercise native Apple/Windows behavior nor resolve any original incident uncertainty.

The later main integration preserved both implementations, audited the new upstream OpenCode fixture boundaries before execution, and passed affected contracts plus a fresh 40/40 aggregate at `/tmp/setup-fixture-matrix-u3o1b6du`. No new containment refusal or unexpected real effect was observed; this was not a syscall-wide effects audit. All historical roots remain retained. No collector follow-up or cleanup occurred. Parent's publication authorization and checkpoint commit do not erase this incident or turn AC10 into an unqualified pass.
