# BB plugin refresh during machine setup

## Status

The user approved the recommendations in design questions Q1–Q6 and the consolidated implementation plan, then delegated implementation to a sole subagent. TASK-64 (formerly branch-local TASK-60) implements the plan with shared embedded policy, caller wiring, documentation and contained offline fixtures. Implementation and post-rebase verification are complete; the user subsequently authorized publication to remote main. The initial implementation's 0.44.0-only gate and custom per-plugin result verification are historical. Following the [0.45.0 source review and Devinabox failure](../research/2026-10-09-bb-plugin-refresh-045-contract.md), the owner chose native CLI delegation to reduce code and avoid recurring release gates. The decisions below reflect that revision. The [original API/identity evidence](../research/2026-10-01-bb-plugin-refresh-api.md) retains its historical validation and limitations. Neither implementation authorizes live setup or plugin updates during development.

## Desired outcome

Ordinary machine setup refreshes the installed plugins of eligible local bb servers belonging to the account being configured. Refresh is separate from installing/updating bb itself, preparing an execution machine, or refreshing marketplace discovery metadata.

See the terminology in [GLOSSARY.md](../../GLOSSARY.md).

## Agreed decisions

### Scope (Q1)

- Include verified local, account-owned servers: setup-managed Ubuntu servers, desktop's local server, and manually installed servers.
- Never update a remote server merely because the machine is enrolled with it or desktop connects to it.
- A prepared CLI or enrolled execution machine alone does not establish a local server with plugins.
- Plugin refresh is independent of the Ubuntu `BB_SERVER` installation/lifecycle opt-in. This deliberately broadens the existing unset/`0` no-touch policy for plugin refresh only; it does not authorize provisioning or lifecycle changes to those servers.

### Plugin selection (Q2)

- Use bb's native update mechanism for every installed plugin with an eligible compatible update.
- Preserve source intent, version pins, local development sources, and disabled status.
- Include disabled plugins where native updates preserve their disabled status; never enable them just to update them.
- Do not install additional plugins, remove/reinstall pinned plugins, force incompatible versions, or independently replace plugins bundled with bb.
- Preserve plugin settings, secrets and schedules through the native mechanism; do not edit the plugin database or package stores directly.

### Failures and reporting (Q3)

- Identity/preflight failures, a nonzero native CLI exit or timeout make the final setup result unsuccessful.
- Delegate plugin compatibility, source selection and update outcomes to BB. Accept its zero-exit skips/rollbacks without independently parsing or verifying per-plugin results; this is the owner's explicit simplicity trade-off.
- Continue unrelated setup work and normal log finalization/upload. Report native command completion, not proof that every plugin updated or every required workflow is ready.

### Stopped servers (Q4)

- Do not start bb solely to refresh plugins.
- A verified stopped installation produces an explicit deferral, not an update-success claim or a failure by itself.
- Existing opted-in Ubuntu startup behavior remains unchanged. Refresh that server after its normal readiness checks succeed.
- Do not launch desktop or manually installed servers for this operation.

### Running servers and activation (Q5)

- Native update/activation is permitted during ordinary setup, even if plugin-provided functionality is interrupted.
- Do not force a server restart or terminate threads to make plugin updates succeed.
- Preserve bb's native rollback behavior. Setup accepts the native CLI's exit status rather than independently classifying rollback results.

### Safe mode (Q6)

- Never disable plugin safe mode.
- Safe mode produces an explicit deliberate deferral, not a failure by itself.
- Do not confuse intentional safe-mode deferral with a failed source/network operation.

## Approved implementation plan

1. Add a shared plugin-refresh policy and standalone entry-point wiring, preserving existing platform, account, headless, readiness, ownership and credential safeguards. Retain native Windows's unsupported-BB boundary and Windows/WSL early exact-headless rejection; do not add a Windows BB installer or a cross-OS updater.
2. Discover eligible servers through trusted local installation/configuration evidence. Verify account ownership and local server identity before mutation. Do not trust an inherited CLI/server selection, a loopback URL alone, or a CLI's presence as proof of a local server. Deduplicate references to the same instance, preserve custom configuration, and refuse uncertain targets rather than reaching a remote server or modifying another account's installation.
3. Run refresh once per eligible local server after applicable existing BB installation/readiness work. Keep it independent of Pi configuration and machine-preparation deferrals. Leave stopped instances and safe mode untouched.
4. Run the verified server package's bundled `bb plugin update --all --yes` once, using its Node executable, explicit loopback URL/data directory and a minimal environment that excludes inherited CLI, proxy, Node and remote controls. Retain bounded identity/readiness/safe-mode checks; remove the release allowlist, update/source/inventory API machinery and post-update verification. Bound execution, suppress raw CLI output in the structured diagnostic protocol, and propagate command failure/timeouts without guessing at plugin outcomes.
5. Add offline fixtures for discovery/identity, explicit CLI/target/environment selection, accepted future versions, zero/nonzero exit semantics, timeouts, safe-mode/stopped deferrals and real extracted caller aggregation. Replace HTTP, process and CLI effects with inert fixtures before helper execution. Never run live setup, BB or plugin code for validation.
6. Update agent guidance and supporting design/research to distinguish plugin refresh from BB installation/preparation/server lifecycle, revise the unset/`0` preservation language narrowly, and increment every modified setup script's version. Following the rebase onto `adce1d4`, preserve upstream's concise human README rather than restoring the removed operator-manual sections.

## Verification requirements

Before any behavioral fixture execution or source-loader change, read and follow the [fixture execution audit](../research/2026-09-29-fixture-execution-audit.md) and [incident record](../research/2026-09-29-fixture-containment-incident.md). Use its sanitized runner, mandatory kernel filter/self-test, private roots/stdio, extracted definitions/callers, inert commands, copied native fixture runtimes, and sequential suites. Stop on containment/preflight failure or unexpected real effects; no uncontained fallback.

Coverage must include:

- No BB, prepared-only, enrolled-only, remote-selected, stopped, safe-mode and running local-server cases.
- Desktop/server aliases, custom configuration and ambiguous/foreign identity without unintended targeting or lifecycle changes.
- Native CLI delegation without per-plugin source/inventory/update HTTP calls; zero-exit native outcomes accepted without parsing; nonzero exit and timeout failures. Native pins/local/builtin/disabled/compatibility/rollback semantics remain BB's responsibility, not independently established by mocked CLI results.
- Exact bundled command and local target; inherited remote/re-exec/proxy/Node controls excluded; unsafe CLI files or changed process evidence refused. Malformed identity/safe-mode responses still fail before the CLI.
- Nonzero final setup results after failed refresh, with unrelated work and logging still reached.
- Unchanged BB preparation, desktop and server contracts; setup-default and extraction/containment contracts; affected reliability, headless, shared-runtime and macOS readiness contracts through the audited runner.
- Shell syntax, ShellCheck on modified Bash scripts, embedding consistency where applicable, and available PowerShell wrapper coverage.

Offline fixtures do not establish native macOS/Windows/WSL/ARM/Bazzite behavior or BB/plugin continuity. Optional fixture skips and missing native evidence must remain explicit. Real rollout is separate and needs authorization.

## Evidence gathered during design

Read-only repository and installed-BB inspection established:

- Existing setup has separate BB desktop, server and execution-machine preparation policies, and no plugin-refresh call sites.
- The installed CLI exposes `bb plugin update --all --yes`; `bb plugin outdated --json` provides structured update checks.
- Plugin updates are server-side operations and can activate code immediately. Safe mode can refuse activation.
- The inspected CLI can print unavailable/skipped or rolled-back results without a failing process exit. The original design independently verified these outcomes; the later owner-approved revision explicitly accepts native exit semantics instead. Command completion therefore remains distinct from verified plugin or workflow readiness.

These are facts about the inspected implementation, not a promise that every installed BB version has the same interface. Unsupported or unverified native capabilities must not be bypassed through direct database/package mutations.
