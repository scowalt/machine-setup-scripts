# TASK-69 offline implementation evidence

## Scope and source review

Implemented from approved checkpoint `c1470dd` (base `414f0f3`) on `bb/implement-task-69-infisical-non-management-thr_99vn7c7irm`. The clean starting branch descended from `integration/task-69-infisical-non-management`. Before commit, `git merge --ff-only integration/task-69-infisical-non-management` reported already up to date at `c1470dd`; no changed source needed revalidation. Parent retains final closure and independent review.

All six entry points drop Infisical-only helpers, requests, state, diagnostics and update prerequisites. No installation, replacement repository, permanent ban or generic-update exclusion is added. Personal Doppler, work-machine selection, account/headless/readiness/trust/OpenCode gates, unrelated failure aggregation and log finalization remain. Versions: Ubuntu **293**, Pi **242**, WSL **225**, macOS **264**, Bazzite **143**, Windows **172**.

Static comparison with the checkpoint proves everything before the task callers is byte-identical after removing only the retired helper blocks; everything after the callers, including logging wrappers, is unchanged. Caller diff review finds only retirement removal, associated update unwrapping and version changes. The [original plan](../plans/2026-09-23-001-retire-infisical.md) is marked superseded; historical research/incident records and the general retired-tool cleanup decision remain intact. README is unchanged.

Six obsolete retirement fixture files are removed. Their replacement is `tests/infisical-non-management-contract.sh`, the nine-method Python caller suite and its Windows AST fixture. CLT, Homebrew-result and reliability contracts no longer demand retirement. Reviewed `tools/run-pre-push-contracts.py`, `tests/extract_setup_fixture.py`, `tests/test_fixture_containment.py` and PowerShell required-name selection: none requires a retired name. The aggregate discovers the replacement shell contract automatically; no dispatcher/filter/extractor relaxation is needed.

## Execution-boundary review

Read `CLAUDE.md`, `GLOSSARY.md`, the [fixture audit](2026-09-29-fixture-execution-audit.md), [incident](2026-09-29-fixture-containment-incident.md), [rollback](2026-09-30-setup-rollback.md), and TDD test/mocking guidance before execution. The user-approved seam is the real extracted task caller plus logging wrapper, not removed retirement internals.

- Bash imports selected definitions only and validates each candidate with the existing reciprocal-delimiter parser before evaluation. All other setup dependencies are inert before invoking `main`. Real secrets-manager branches, APT Doppler helper and selected headless/readiness gates remain; sudo/curl/Homebrew effects are recording functions, never native package-manager requests. The absolute secondary-macOS shellenv command is also an inert function.
- Windows parses the full source without evaluation, selects/revalidates individual `FunctionDefinitionAst` nodes, installs dependency mocks, then invokes the real wrapper. Transcript/transport/WinGet effects are inert; its only log-directory creation is beneath the private fixture root. There is no registry inspection.
- Absent/residual scenarios run twice against the same private HOME. Synthetic malformed legacy metadata, a custom binary sentinel, symlink, environment, Doppler state and project data retain bytes/modes/link targets. Recorded requests, result, eligible updates, reboot ordering and finalization are asserted. Required failures, personal/work classifications, macOS main/secondary boundaries, Doppler presence/trust, readiness and exact headless rejection are covered.
- Existing CLT/Homebrew/reliability fixture edits remove only obsolete expectations; their extraction and mocking boundaries are unchanged. The additional BB plugin-refresh suite was fully reviewed before its separate run: validated Python definitions, synthetic metadata/process/socket APIs, inert callers and temporary roots; no installed BB code or process inventory executes.

All behavioral runs used the unchanged sanitized sequential runner, mandatory compiler/kernel-filter self-test, private stdio/roots and explicit existing tools. PowerShell `/tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh` was executable and identified as native ELF before use, then successfully parsed/executed the contained AST fixtures. Node, mise, Chezmoi and Bun were also existing native ELF binaries. No tools were installed or fetched; optional integrations were not enabled.

## Red/green slices

Each row ran this exact command against the then-current source:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh \
  --tool-path /usr/bin:/bin tests/test_infisical_non_management.py
```

| Slice | Private artifact root | Exit / evidence |
| --- | --- | --- |
| APT/WSL red | `/tmp/setup-fixture-matrix-gckwty5n` | 1; obsolete retirement request observed; Ubuntu/Pi eligible update absent |
| APT/WSL green | `/tmp/setup-fixture-matrix-ayo2nwy8` | 0; one parameterized method |
| Homebrew red | `/tmp/setup-fixture-matrix-v_e3jnkw` | 1; APT passes, main/secondary retirement requests remain and eligible upgrades defer |
| Homebrew green | `/tmp/setup-fixture-matrix-st5kkpal` | 0; two methods |
| Windows red | `/tmp/setup-fixture-matrix-hdgn5ypq` | 1; Bash passes, retirement request remains and both update phases defer |
| Windows green | `/tmp/setup-fixture-matrix-id37g7g5` | 0; three methods |
| Failure preservation | `/tmp/setup-fixture-matrix-gvb4opl7` | 0; five methods, no extra production changes needed |
| Gates/Doppler/source preservation | `/tmp/setup-fixture-matrix-tipxfuye` | 0; nine methods, no extra production changes needed |

Red failures are behavioral assertions, not containment refusals. Red runs also report missing-update `ValueError` assertions where the obsolete gate omitted the expected event. Each artifact root retains `results.json`, private suite log, compiler log and successful socket-denial self-test log. No historical artifacts were removed.

## Aggregate and static results

The complete existing dispatcher ran sequentially:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tools/run-pre-push-contracts.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh \
  --mise /home/scowalt/.local/bin/mise \
  --chezmoi /home/scowalt/.local/bin/chezmoi \
  --bun /home/scowalt/.bun/bin/bun
```

**Exit 0, 42/42 entries**, zero failures/timeouts, artifacts `/tmp/setup-fixture-matrix-mbwoo4od`. `results.json` enumerates all exact suite paths/results. Includes setup-default, extraction/containment, hook dispatch, CLT, Homebrew, reliability, reboot, headless, BB desktop/preparation/server, Pi/runtime/OpenCode/skills and weekly contracts. Reported unittest executions: **493 methods including 16 skips** (not unique test passes); OpenCode Node: **116 cases, 115 passed, one skipped**. TASK-69: **9/9 methods, no skips**. Actual Windows syntax/AST selection: **132 function definitions**, without top-level execution.

BB plugin refresh is not in that dispatcher's shell inventory, so it was additionally run using the red/green command above with only the final suite argument changed to `tests/test_bb_plugin_refresh.py`: **exit 0, 24/24 methods, no skips**, `/tmp/setup-fixture-matrix-0bjtsst1`.

Static commands all returned 0:

```bash
for file in ubuntu.sh pi.sh wsl.sh mac.sh bazzite.sh \
  tests/setup-reliability-contract.sh tests/infisical-non-management-contract.sh; do
  /bin/bash -n "${file}" || exit
done
/usr/bin/shellcheck ubuntu.sh pi.sh wsl.sh mac.sh bazzite.sh \
  tests/setup-reliability-contract.sh tests/infisical-non-management-contract.sh
git diff --check
git diff --cached --check
```

Python `ast.parse` passed for the three changed/new Python test files. Exact static command arrays/results and preservation/version assertions are in `task69-static.json` beside the aggregate; `task69-source-sha256.json` fingerprints tested sources and unchanged containment machinery. An initial ad-hoc version check selected the embedded shared-policy version rather than the caller banner; restricting that read-only check to the caller fixed the assertion. No production/test code or containment changed for that correction.

## Skips, hook limitations and non-claims

The aggregate's 16 unittest skips are: Bash 3.2 (1), AskClaude external dotfiles (1), managed-skill native CLI discovery/snapshot and external dotfiles (3), Go installed catalog/native lock (2), native Windows profile ACL/races (2), Pi package external dotfiles/installed registry probe (2), runtime external-dotfiles convergence (1), Paseo external dotfiles (1), and repeated optional managed-skill cases in weekly regressions (3). OpenCode's installed `cmd-shim` comparison adds one Node skip. Native Windows Backlog handle/ACL operations have a separate diagnostic omission; AST/C# compilation is not native execution proof.

No trusted installed Markdownlint was found. Shared mutable `bunx` caches were neither executed nor repaired; no download was attempted. Markdown changes received manual formatting/local-link review, not a claimed lint pass. The commit uses the existing native Lefthook/Gitleaks path with `LEFTHOOK_EXCLUDE=shellcheck,markdownlint` to avoid `bunx`; standalone ShellCheck supplies the skipped shell lint check. This is an explicit Markdownlint omission, not a full hook pass. Native `/home/scowalt/.local/share/mise/installs/gitleaks/8.30.1/gitleaks protect --staged --no-banner --redact` also passed (exit 0); output is `task69-gitleaks.log` beside the aggregate.

Linux PowerShell is not native Windows/PowerShell 5.1, registry, WinGet or Windows-update evidence. Native macOS/Apple/BSD, WSL/Bazzite/ARM, real package-manager behavior and BB/session continuity remain unverified. Ordinary setup is still potentially disruptive. No live setup, app/skill/service, package operation, upload, credential/account action or fleet change occurred during validation. No containment refusal or unexpected real effect was observed; this is not a syscall-wide effects audit. Original incident receipt/retention/telemetry uncertainty remains unchanged. Offline passing evidence does not authorize rollout.
