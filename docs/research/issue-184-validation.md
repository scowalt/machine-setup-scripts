# Issue #184 integrated validation

Implements acceptance child [#188](https://github.com/scowalt/machine-setup-scripts/issues/188) on integration `8feb79d2d07f8c1fcde719578d0f9696643b576d`, containing #185–#187. **43/43 final inventory entries pass; standards/spec two-axis review remains pending with the parent.** No issues are closed and nothing is pushed by this child.

## Coverage and execution boundary

The [authoritative spec](https://github.com/scowalt/machine-setup-scripts/issues/184) names the existing installer, policy/wrapper and caller seams. Existing coverage was retained rather than duplicated:

- [Desktop fixtures](../../tests/test_bb_desktop.py): `MacApplicationsTests` exercises the real native-query decoder/parser, signed/unsigned identity, unrelated rows, foreign refusal, running deferral, promotion rechecks and bundle preservation.
- [Plugin fixtures](../../tests/test_bb_plugin_refresh.py): `Discovery` and `NativeEvidence` exercise real Darwin inventory/per-process interpretation, account filtering, accepted-peer/native-contract proof, changed evidence and source/disabled-state/deferral preservation. `Callers.test_shared_embedding_windows_boundary_and_real_failure_aggregation` covers all five Bash callers.
- [OpenCode fixtures](../../tests/test_opencode_cli_callers.py): `test_real_installer_wrapper_caller_and_finalization_with_two_accounts` and `test_real_powershell_installer_caller_and_finalization` carry real discovery failures through wrappers and finalization. [Node cases](../../tests/opencode-cli.test.cjs) supplement native delimiter, bounds, forgery, rollback and secondary diagnostic failure coverage.
- [Homebrew results](../../tests/test_homebrew_results.py): `test_failed_upgrade_reaches_final_result_and_log`, `test_clt_warning_does_not_block_successful_upgrade_or_poison_final_result` and `test_success_does_not_erase_an_earlier_failure` already prove actual failure versus warning-only success under [ADR 0007](../adr/0007-use-operation-results-instead-of-clt-compatibility-gates.md). [CLT caller tests](../../tests/test_macos_clt.py) retain ordinary work, bootstrap and selection boundaries.

The sole new method is `Callers.test_early_failure_survives_success_deferral_reboot_and_completed_log` in the plugin fixtures. Six cases combine desktop/OpenCode failure or a success control with stopped/safe-mode deferral. They retain the complete real macOS `run_setup_tasks`, `main`, `refresh_bb_plugins`, `start_setup_log` and `finish_setup_log` definitions from [mac.sh](../../mac.sh). They verify later independent success, deferral, Pi work, reboot reporting, final status and a completed on-disk log; the inert upload copy must equal the drained log. Failure controls cannot become successful summaries, and deferrals alone remain successful.

Before execution, reviewed merged fixture changes and this new boundary against the [execution audit](2026-09-29-fixture-execution-audit.md) and [incident](2026-09-29-fixture-containment-incident.md). Definitions-only extraction is unchanged. Every other setup helper is replaced before invocation; native inventory, package/lifecycle commands and transport are inert. Real log creation/tee/draining and upload-copy writes stay inside the private fixture HOME. No production test API, umbrella framework or production change was needed.

## Red/green evidence

Each root below contains private preflight diagnostics, suite logs and `results.json`. Component records in `/tmp/issue-184-coordination/` retain full commands, secondary regressions and counts; the table records representative defect reproductions, not native repairs.

| Component | Red artifact root | Green artifact root | Result |
| --- | --- | --- | --- |
| Desktop #185 | `/tmp/setup-fixture-matrix-_5_xjy1f` | `/tmp/setup-fixture-matrix-3cs_ypir` | 88 methods: two signed-UID errors become zero; unsigned controls already pass. Final component matrix: `/tmp/setup-fixture-matrix-sz1ap69f`, 9/9 entries, 101 desktop methods. |
| Plugin #186 | `/tmp/setup-fixture-matrix-8lcaxo6z` | `/tmp/setup-fixture-matrix-j0eochhp` | 34 methods: two signed-inventory subcases repaired. Per-process follow-up: `/tmp/setup-fixture-matrix-4pwt_r61` → `/tmp/setup-fixture-matrix-c80ml4__`, four errors repaired in 35 methods. Final component root: `/tmp/setup-fixture-matrix-z1q7pyhk`, 6/6 entries. |
| OpenCode #187 | `/tmp/setup-fixture-matrix-8jsosfxk` | `/tmp/setup-fixture-matrix-kljieszc` | 12 methods: five real discovery-to-wrapper diagnostic failures repaired. Extra-record/NUL and forged-object cycles are in `opencode-evidence.md`; final merged component root `/tmp/setup-fixture-matrix-1p182j97`, 3/3 entries. |
| Integrated #188 | `/tmp/setup-fixture-matrix-505swdr6` | `/tmp/setup-fixture-matrix-kehfad8v` | Regression sensitivity, **not a new production defect**: an in-memory caller mutation erased prior failures before refresh. Four failure cases went red; two success controls passed. Removing that mutation gives 43 plugin methods, eight containment methods and eight default/environment methods passing across 3/3 entries. |

Component detail: [desktop evidence](/tmp/issue-184-coordination/desktop-evidence.md), [plugin evidence](/tmp/issue-184-coordination/plugin-evidence.md), [OpenCode evidence](/tmp/issue-184-coordination/opencode-evidence.md), [merge evidence](/tmp/issue-184-coordination/merge-evidence.md). The temporary mutation exists only in [red sensitivity evidence](/tmp/issue-184-coordination/integration-red-sensitivity.patch), not the committed tests or production source.

## Final complete inventory

Exact command, from the final source checkout (C-locale glob expansion sorts all 37 shell entries, with no duplicate entry paths):

```bash
export LC_ALL=C
flock /tmp/issue-184-coordination/fixtures.lock env -i PATH=/usr/bin:/bin \
  /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh \
  --tool-path /tmp/issue-184-coordination/native-tools:/usr/bin:/bin --timeout 600 \
  tests/test_fixture_containment.py tests/test_pre_push_contracts.py \
  tests/test_macos_clt.py tests/test_homebrew_results.py \
  tests/test_managed_skill_suite.py tests/test_bb_plugin_refresh.py tests/*.sh
```

Artifacts: [/tmp/setup-fixture-matrix-wibga34a](/tmp/setup-fixture-matrix-wibga34a). **43/43 entries exit 0, zero timeouts**, in 1,112.4 suite-seconds. Mandatory compiler/kernel-filter self-test and private stdio remain unchanged. No optional integration variables were inherited; no tools were installed.

Logs report **559 unittest method executions: 543 pass, 16 skipped**, plus **140 OpenCode Node cases: 139 pass, one skipped**. These are executions, not unique tests: some shell contracts dispatch the direct Python suites again. Shell and available Linux PowerShell contracts also pass; shared-runtime PowerShell reports 1,409 assertions on each of two runs. Exact per-entry counts, inventory and source hashes are linked from [integration evidence](/tmp/issue-184-coordination/integration-evidence.md).

Skips remain explicit:

- Managed skills native CLI discovery/snapshot and external dotfiles: three methods, executed twice (six skips).
- External AskClaude/adapter dotfiles (one), Go installed catalog/lock (two), Pi package dotfiles/registry integrations (two), shared-runtime dotfiles (one), Paseo external source (one).
- Existing Bash 3.2 unavailable (one); native Windows profile ACL/handle races (two). Backlog additionally reports a native Windows handle/ACL omission outside unittest counts.
- Optional installed OpenCode command-shim integration (one Node skip).

## Static checks and handoff

After the final inventory, all three embedding `--check` tools, desktop payload equality, cumulative changed Bash syntax/ShellCheck, Python AST and Node syntax, contained PowerShell AST parsing, setup banners and whitespace checks pass. [Static command](/tmp/issue-184-coordination/integration-static-checks.sh) and [log](/tmp/issue-184-coordination/integration-static.log) record them. A 107-file manifest verifies executable sources did not change after the matrix. Integrated versions remain macOS 272, Ubuntu 302, Pi 248, Bazzite 151, WSL 231, Windows 176; this test/documentation-only child changes none.

Native staged Gitleaks reports no leaks. Commits use command-local `LEFTHOOK=0` to avoid tool-installing `bunx`; no global hook configuration changes. The complete contained inventory and explicit native checks substitute for those hook commands. Trusted Markdownlint is unavailable; Markdown formatting and local links were checked without installing a replacement, not claimed as a Markdownlint pass.

No new containment refusal or unexpected real effect was observed; this is not a syscall-wide effects audit. No live setup, app/skill/plugin/extension execution, process inventory, machine repair or rollout occurred. Linux PowerShell is not native Windows/ACL/PowerShell 5.1 evidence; native Apple/BSD/GUI, ARM/WSL/Bazzite and BB session/plugin continuity remain unverified. Earlier containment-incident remote receipt/telemetry uncertainty is unchanged.

The original OpenCode PATH refusal remains unreproduced and unattributed: these diagnostics do not identify fish, mise or another historical cause, nor prove the affected installation repaired. Parent retains integration, two-axis review and finding resolution, PR #189 updates, issue closure and worktree cleanup.
