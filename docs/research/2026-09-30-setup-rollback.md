# TASK-58: restore ordinary machine setup

## Decision and scope

The user approved rolling back the non-disruptive default after an Ubuntu run deferred essentially all provisioning and failed the new Code/log path checks. Merge `daa420c` introduced that behavior; its first parent, `e169f8d`, already contains the unrelated OpenCode HTTP/header and private Homebrew-group fixes.

All six entry points again run their ordinary provisioning/update workflow without a maintenance switch. The blanket scheduling guards, observation-only dispatcher and newly introduced Code/log ancestor-permission policy are removed. Normal component-specific trust, platform, exact-headless, opt-out, recovery and failure aggregation remain. Bash log startup is best-effort again; Windows retains its pre-change fail-before-task-dispatch logger behavior and finalization.

**This restores potentially disruptive setup.** Packages, services, runtimes, dotfiles and connectivity can change during a normal run, including BB service restarts. Protect ongoing work and choose an appropriate window. No automatic reboot was added.

Retained exceptions to a mechanical merge revert:

- Data-only dotenv readers, literal credential characters, controlled syntax failures and Ubuntu's process `BB_SERVER` precedence. Canonical readers remain in `lib/setup-policy.{bash,ps1}`; `tools/embed-setup-policy.py` now embeds environment policy only, never scheduling guards. Windows loads the reader after the existing early headless gate and placeholder step.
- Definitions-only Bash/PowerShell/Python fixture imports, copied native runtimes, sanitized temporary roots and kernel/FD containment.
- All historical incident and validation records. Earlier task acceptance is historical, not evidence for the reverted default or native rollout. TASK-57's unresolved incident exception is not retroactively cleared.

Setup versions: macOS **258**, Ubuntu **285**, Pi **236**, Bazzite **137**, WSL **219**, Windows **168**.

## Source-preservation review

A static comparison normalized only the new environment-reader blocks, their call-site replacements, Ubuntu's local platform selector and version headers. **All six resulting files exactly match `e169f8d`.** This covers unchanged package/runtime/BB/Pi/skills/CLT behavior and old Code/log/lock handling, rather than relying only on a list of selected functions.

The three OpenCode policy libraries, OpenCode Node/native-proof fixtures, kernel filter and native-runtime-copy helper remain byte-identical to the starting checkout. The fixture extractor's only functional adjustment is replacing the removed policy initializer in its required-name set with the retained environment loader; its syntax/delimiter rejection remains intact. PowerShell still imports function ASTs only. Removing maintenance preambles never reinstates whole-script evaluation.

Current contract names are `tests/setup-default-contract.sh`, `tests/test_setup_rollback.py` and `tests/test_setup_environment.py`, replacing the obsolete default-deferral contract. Existing caller contracts now invoke ordinary setup wrappers with mocked effects, without maintenance switches. Synthetic changed-signature extraction tests intentionally retain arbitrary old-style arguments to verify that entry syntax cannot escape definitions-only imports.

## Offline evidence

| Stage | Private artifacts | Result |
| --- | --- | --- |
| Red rollback regression | `/tmp/setup-fixture-matrix-kl92cu9d` | Three methods failed across 22 subcases: normal-wrapper dispatch and group-writable fixture log paths rejected the old policy. |
| Extraction and rollback cohort | `/tmp/setup-fixture-matrix-_7vlbvsx` | Both entries pass: eight containment/extraction methods and eight rollback/environment methods. |
| Audited aggregate | `/tmp/setup-fixture-matrix-fz7qu0cp` | **40/40 entries pass**, zero failures/timeouts. |
| Final version-docstring cohort | `/tmp/setup-fixture-matrix-asp5n8kk` | Homebrew results, OpenCode CLI, Pi package maintenance and shared runtime: **4/4 pass**. |

The aggregate uses all 36 contract shell entries plus direct extraction/containment, CLT, Homebrew-result and managed-skill Python suites. It reports **475 unittest methods including 15 skipped executions**, plus **98 OpenCode Node cases: 97 pass, one optional skip**. Native Windows Backlog handle/ACL operations also remain an explicit diagnostic omission. Optional external-dotfiles, installed Pi/skill/extension/catalog/lock and command-shim integrations were not enabled. These are skips, not coverage.

The rollback regression uses real extracted Bash and Windows wrappers, with all task/lifecycle/transport effects mocked before invocation. It verifies ordinary dispatch, preservation of actual task failures through finalization, best-effort Bash logger failure, and unchanged fixture Code contents/modes with group-writable HOME/Code/log ancestors inside a private enclosing root. It does not inspect or repair the reported real machine.

The aggregate ran sequentially with this explicit existing-tool selection and the mandatory compiler/filter self-test:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh \
  --tool-path /usr/bin:/bin:/tmp/task56-audited-tools-wn5n3t7y --timeout 300 \
  tests/ai-coding-agent-contract.sh tests/attention-span-removal-contract.sh \
  tests/backlog-mcp-retirement-contract.sh tests/bb-desktop-contract.sh \
  tests/bb-machine-preparation-contract.sh tests/bb-server-contract.sh \
  tests/claude-code-installation-contract.sh tests/codex-profile-isolation-contract.sh \
  tests/gitea-client-installation-contract.sh tests/headless-contract.sh \
  tests/infisical-retirement-contract.sh tests/kubectl-installation-contract.sh \
  tests/setup-default-contract.sh tests/ntn-installation-contract.sh \
  tests/opencode-cli-contract.sh tests/opencode-go-wiring-contract.sh \
  tests/paseo-non-management-contract.sh tests/pending-reboot-contract.sh \
  tests/pi-askclaude-contract.sh tests/pi-companion-packages-contract.sh \
  tests/pi-model-defaults-contract.sh tests/pi-opencode-go-contract.sh \
  tests/pi-package-maintenance-contract.sh tests/pi-profile-permissions-contract.sh \
  tests/pi-prose-contract.sh tests/pi-rpiv-removal-contract.sh \
  tests/pi-skill-ownership-contract.sh tests/pi-subagents-removal-contract.sh \
  tests/pi-zai-provider-contract.sh tests/rtk-removal-contract.sh \
  tests/setup-reliability-contract.sh tests/shared-node-runtime-contract.sh \
  tests/simple-english-skill-contract.sh tests/telegram-alerts-contract.sh \
  tests/weekly-log-audit-regressions.sh tests/windows-log-upload-contract.sh \
  tests/test_fixture_containment.py tests/test_macos_clt.py \
  tests/test_homebrew_results.py tests/test_managed_skill_suite.py
```

Syntax and ShellCheck pass on all 14 changed/new Bash files. Changed Python sources parse; actual Windows AST selection passes under containment. Both embedding checks and whitespace checks pass. `rollback-preservation.json` and a 42-file changed-source manifest are retained alongside the aggregate. Four versioned Python test docstrings were bumped after the aggregate without changing executable code; the final affected-suite cohort above passes with the same runner/tool arguments and only those four suite paths.

Markdownlint is unavailable as a trusted installed command. The previously documented untrusted shared cache was not executed or repaired; no package was downloaded. Manual Markdown review and repository-link checks supplement this omission, not a claimed lint pass.

## Limits and live-operation boundary

No live setup, application/skill/extension execution, package update, service restart, credential change, Tailscale operation, collector investigation or fleet rollout was performed. No unexpected real effect or new containment refusal was observed; this is not a syscall-wide effects audit. Kernel containment is not a filesystem/process sandbox.

Linux PowerShell fixtures do not verify native Windows ACLs/PowerShell 5.1, WinGet or services. Native macOS/Apple/BSD, ARM/WSL/Bazzite and BB continuity remain unverified. The [earlier incident's remote receipt/retention and telemetry uncertainty](2026-09-29-fixture-containment-incident.md) is unchanged. Passing offline tests do not authorize a live rollout.
