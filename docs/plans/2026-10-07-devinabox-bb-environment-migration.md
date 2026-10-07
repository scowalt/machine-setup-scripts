# Devinabox BB environment migration: design interview

Status: specification published as [GitHub issue #204](https://github.com/scowalt/machine-setup-scripts/issues/204), labeled `ready-for-agent`. This record preserves the agreed constraints and investigation evidence; the issue is authoritative for scoped preparation. Neither publication nor the label authorizes modifying the machine or activating a migration. [Current evidence](../research/2026-10-07-devinabox-setup-failure.md) shows working local BB services but an incomplete setup run caused by rejected customization. APT's two named failures have since recovered.

## Agreed decisions

- Keep [ADR 0011](../adr/0011-scope-bb-server-customizations.md): setup retains BB maintenance responsibility; replace whole-account environment inheritance with supported, scoped BB-native configuration after establishing the required dependencies. Preserve required functionality, not the existing inheritance mechanism.
- A brief planned BB interruption is acceptable in principle. Investigation and preparation remain non-disruptive. Actual activation requires a separately confirmed window, independent operator connection and agreed recovery plan.
- Preserve required BB/provider connections and authenticated agent-launched tools/integrations, not blanket access to unrelated account environment variables. Every enabled, configured integration is required by default unless Scott explicitly excludes it; installed-but-unconfigured tools do not automatically count. Flag apparently stale configurations for Scott rather than silently dropping them. The exact inventory remains a factual prerequisite.
- Record pre-existing integration failures separately, without expanding this migration into unrelated repairs or marking those checks as passing. Pause if such a failure prevents establishing a required workflow's independence from the broad override.
- Acceptance requires bounded end-to-end evidence: browser reconnection, harmless local execution and minimal checks of each required provider/integration. Agree on exact requests and any usage costs before execution; configuration and healthy endpoints alone are insufficient.
- Retain a verified private backup, but stop for Scott's explicit approval before restoring the broad override and restarting after failed activation. Extending downtime for that approval is preferable to automatic reintroduction of whole-account environment inheritance.
- The subject is devinabox's scowalt account and `$HOME/.config/systemd/user/setup-bb-app.service.d/env.conf`. The [existing migration procedure](2026-10-06-bb-environment-override-migration.md) concerns a differently named Beelink override and is not directly executable authority for this machine.

[Required bb workflow](../../GLOSSARY.md) records the agreed preservation boundary. These decisions otherwise reaffirm existing policy; no new ADR is needed.

## Configuration-evidence finding

A [bounded static review of installed BB 0.44.0](/tmp/setup-diagnosis-devinabox-6XGdq3Pz/native-config-evidence-research.md) identified native configuration and contribution mechanisms, but did not establish a fully audited live configured-status/source view meeting the current no-secret-read/no-provider-execution boundary. Masked output does not prove an inert call path: configuration dispatch can load managed environment files, and status/model/usage paths can invoke callbacks or refresh providers. This is an evidence gap, not proof that scoped native configuration is impossible or that BB is unhealthy.

The narrow follow-up traced `GET /settings/machine-environment` through `machineEnvironmentView` and `readMachineEnvironment`. Stored environment rows are mapped to names/notes with `value: null` without decrypting their values, but the response also computes built-in Git health. Unless a global `GH_TOKEN` record exists or automatic Git credentials are disabled, it invokes `gh auth token` and, after successful token parsing, authenticated `gh api user`. The current suppressing conditions were not inspected, and the route has no request switch to suppress this probe. Thus it could not be invoked under the original metadata-only boundary; the separately approved exception below applies only to this inventory request. The traced GET contains no explicit database mutation/provider callback; Git internals and general middleware remain outside the bounded audit.

Even a successful response would prove only global native stored-record names, not enabled integrations, credential usability, effective launch sources or independence from `env.conf`. The next step requires a separately scoped configuration review, not a broad settings/environment dump or repeated exploratory research. Any permission to use existing credentials internally must be explicit, distinguish request authentication from handler-triggered Git credential use, and preserve no-secret-output/no-provider-inference/no-lifecycle-change boundaries. No live query or migration was performed by that research worker; its local evidence artifact is private and ephemeral.

## Separately approved inventory request and result

Scott approved Q8: one native global inventory request, including its possible built-in use of existing GitHub credentials, with only variable names and controlled status fields exposed. This did not authorize credential/configuration changes, provider inference, setup or service operations, or broader configuration queries.

At **2026-10-07 15:16:39 UTC**, `bb machine env list --json`, explicitly targeting the local devinabox BB server, returned **zero global native environment records** and built-in Git status **`logged in`**. A filtering wrapper checked the response schema and withheld values, notes, arbitrary status messages, raw responses and diagnostics. Only the controlled result was retained in [private inventory evidence](/tmp/setup-diagnosis-devinabox-6XGdq3Pz/approved-native-inventory.json).

This establishes neither absence of configured providers/project overrides nor independence from `env.conf`. In particular, the inspected Git resolver invokes `gh` without replacing its inherited environment; a successful current Git check does not identify the credential's source or prove that the next process will authenticate without the override. Provider-specific native configuration and project/provider contributions remain unverified. No migration was performed; the next step still requires per-required-workflow source/precedence evidence, not removal of the override based on an empty global inventory.

## Outstanding evidence and operator-approval gates

- Evidence-based inventory of enabled, configured providers/tool integrations; Scott's exclusions, if any; supported configuration sources and precedence; and bounded acceptance checks/usage budget for each. The inventory must distinguish configured state from installation or registration alone.
- Availability of supported non-secret native configuration/status and precedence evidence, including whether that evidence can establish independence from the broad override. No credential contents or process environments will be read to fill a gap.
- Exact transition, private backup location, stable-state checks, interruption window and recovery decision-maker, followed by explicit confirmation of the complete plan. No implementation or live changes before that confirmation.

Document settled decisions as the interview progresses. Stop before backup/removal/service changes if required configuration evidence is absent or uncertain. A running server, healthy endpoint or credential file's existence does not prove all required workflows will survive the next start.
