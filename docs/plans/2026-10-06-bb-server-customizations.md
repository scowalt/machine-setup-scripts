# BB server customizations: design discussion

Status: Q1–Q6 agreed. [GitHub issue #197](https://github.com/scowalt/machine-setup-scripts/issues/197), labeled `ready-for-agent`, is the authoritative implementation contract; these notes retain the design history. The subsequent owner comment authorizes repository implementation and local commits through `implement-spec` on `integrate/bb-customizations-197`, superseding the design-stage no-commit wording below. Runtime work is tracked in #198 and the [one-time migration procedure](2026-10-06-bb-environment-override-migration.md) in #199. This authorization requires neither a push nor deployment; live migration, service restarts and setup execution remain separately authorized. No live remediation is established by these notes.

## October 9 disposition

[Spec #221](https://github.com/scowalt/machine-setup-scripts/issues/221) and [ADR 0013](../adr/0013-preserve-reviewed-bb-environment-inheritance.md) supersede Q2/Q5's retirement-first requirement and Q6's TMPDIR-only limit **only for the recognized existing app environment references**, including coexistence with reviewed TMPDIR. The owner accepts continued whole-account exposure to retain ordinary setup maintenance without a migration prerequisite. Preserve native inputs/precedence, unrelated state and all remaining trust boundaries. The original decisions, captured refusal and development plan below are history, not current acceptance criteria for that case. No live migration or rollout is established here.

## Evidence

The [2026-10-06 Beelink Ubuntu setup log](https://logs.scowalt.com/logs/scott-beelink-ubuntu/2026-10-06-18-16-57-571.log) records an incomplete setup run at `preflight.unit-dropins` (lines 371–373), consequential BB plugin-refresh deferral (377), and final failure reporting (432). The ordinary Ubuntu version-309 caller preserves the error through unrelated work and logging.

User-authorized read-only Tailscale SSH inspection at 18:45–18:47 UTC confirmed a real, account-owned mode-0700 `~/.config/systemd/user/setup-bb-app.service.d` containing two regular files, both predating the run:

- `10-tmpdir.conf`: sets `TMPDIR=/home/scowalt/.cache/bb/tmp`.
- `20-env-local.conf`: loads `EnvironmentFile=%h/.env.local`.

Systemd lists both as loaded overrides. App and ingress services were active/running; local HTTP health returned `ok=true`, and host-daemon status returned `connected=true`. The app process predated both overrides and had no `TMPDIR` variable. Loaded configuration is therefore not proof of what the existing process is using. No configuration was changed, service restarted, or setup run. No credential values were printed.

At diagnosis, the version-309 `bb_unit_dropins_empty` guard in `ubuntu.sh` deliberately rejected every nonempty local drop-in directory. Contained real-helper/caller fixtures reproduce the failure chain with one zero-byte entry and clear it when only that synthetic entry is removed. Existing empty-directory support is already present. This is a customization-policy conflict, not evidence that the guard malfunctioned or BB crashed.

## Agreed decisions

### Q1: Setup retains server maintenance responsibility

Keep the server setup-managed while supporting reviewed local customizations. Preserve existing overrides during review; do not delete them just to pass preflight or broadly accept arbitrary overrides. A healthy running server does not satisfy an unsuccessful required setup operation.

Vocabulary: **bb server customization**, defined in [GLOSSARY.md](../../GLOSSARY.md), is distinct from making the server unmanaged.

### Q2: Bound the credential/configuration inputs

Use explicitly scoped BB/provider settings rather than endorsing inheritance of every variable from the account's `~/.env.local`. Accepting the existing whole-file override would affect future process starts and could introduce unrelated secrets and conflicting runtime settings. This decision does not authorize deleting credentials, editing the original environment file, or removing the existing override before a reviewed transition is agreed.

### Q3: BB-native configuration is authoritative

Use BB's existing native configuration for explicitly scoped BB/provider settings. Preserve existing credentials and unrelated configuration. Do not add automatic imports or synchronization from `~/.env.local`, a new credential store, or competing precedence rules. This choice does not establish that every desired provider is already configured; current health checks do not prove provider authentication.

### Q4: The temporary directory remains optional

Retain an explicitly selected, reviewed private BB temporary directory on Beelink rather than imposing a new default on every setup-managed Ubuntu server. Machines without this customization retain their existing behavior. The observed incident proves a preflight conflict, not a fleet-wide need for a different temporary directory.

### Q5: The broad environment override needs an explicit migration

Removal of the existing `20-env-local.conf` is a separately authorized one-time migration, not ordinary setup cleanup. Privately back up the exact reviewed override outside systemd's drop-in directory, preserve `~/.env.local` and native BB credentials, and establish the required configuration through non-secret evidence before removal. Preserve state and stop if configuration cannot be established; do not guess or silently import missing credentials. Until the migration is completed, setup remains explicitly incomplete rather than claiming success.

### Q6: Support only the reviewed temporary-directory customization

Support the reviewed `TMPDIR=$HOME/.cache/bb/tmp` choice with strict ownership, link, content and loaded-override checks. Retain absent/verified-empty directory behavior. Unknown directives, other paths, conflicting overrides and unverified metadata remain failures, without automatic permission repair. The separate environment drop-in is mode 0664; supporting the safe TMPDIR customization must not implicitly bless that file.

The consequential maintenance and credential boundary is recorded in [ADR 0011](../adr/0011-scope-bb-server-customizations.md).

## Consolidated development plan — published in issue #197

1. Add failing contained fixtures at the real Ubuntu service-preflight/caller seam for the reviewed TMPDIR-only case. Keep the captured two-file state failing because its broad environment override still needs explicit migration.
2. Extend Ubuntu BB service preflight narrowly to verify the reviewed customization, its selected temp location, and the exact loaded override selection. Do not implement a general systemd override interpreter. Preserve parent-first path checks, stable filesystem evidence, unit identity and pre-mutation revalidation. Reject unavailable or unsafe state rather than creating or repairing it implicitly.
3. Preserve customization bytes and unrelated state. Do not write a new fleet-wide TMPDIR default, change native BB/provider configuration, import environment-file credentials, or retire either override during ordinary setup. Improve controlled diagnostics so a supported TMPDIR override is distinguishable from the unsupported broad environment override or unknown customization.
4. Cover unknown/extra directives, duplicate/conflicting settings, alternate paths, links, unsafe ownership/modes, changed evidence, unexpected loaded drop-ins and inspection failures. Assert refusal before lifecycle/package changes, unaffected-work continuation, plugin-refresh readiness gating and final failure/log preservation. Preserve existing no-drop-in and verified-empty behavior.
5. Bump the modified Ubuntu script version. Run Bash syntax and ShellCheck, embedding consistency where applicable, and the mandatory contained extraction/default, BB server, relevant plugin-refresh/preparation, reliability, headless and shared-runtime contracts. Broaden the affected matrix if shared helpers or callers change. Record skips and distinguish offline results from native rollout.
6. Present the repository changes and the separate one-time migration procedure for review. At design approval, no commit/push, live migration, permission repair, service restart, provider-auth/model request or setup rerun was implied. The subsequent implementation authorization permits local commits as recorded above; live operations still need separate authorization.

Success for development means the safe TMPDIR-only fixture passes, unknown/broad overrides still fail without mutation, and required contained regressions pass. It does not mean Beelink's next unchanged setup run succeeds: the agreed one-time environment-override migration remains a prerequisite.

## Existing constraints

`setup_bb_server`, `bb_config_merge_native`, and the generated guard in `ubuntu.sh` are the implementation references. Native configuration writes already use BB's locks and preserve unrelated provider/configuration data. Preserve the stopped-update transaction, saved endpoint, readiness-gated ingress, credential confidentiality, unrelated routes, independent plugin-refresh behavior, failure aggregation and log finalization.

Behavioral validation must use the [audited contained fixture runner](../research/2026-09-29-fixture-execution-audit.md), not live setup or application/plugin execution. The earlier isolated diagnostic and passing contracts do not establish a successful future rollout or uninterrupted native sessions.
