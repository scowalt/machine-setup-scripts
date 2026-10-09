# Retire the reviewed BB environment override

**Historical procedure; superseded for the preserved-reference path.** [Spec #221](https://github.com/scowalt/machine-setup-scripts/issues/221) and [ADR 0013](../adr/0013-preserve-reviewed-bb-environment-inheritance.md) support the recognized existing app reference, alone or with reviewed private TMPDIR, rather than requiring retirement before ordinary maintenance. The original refusal, approval and recovery rules below describe that earlier retirement proposal, not prerequisites for the supported update path. They authorize no live action and establish no completed migration; any future retirement needs a newly reviewed scope.

This is a **one-time operator procedure, not an executable migration or authorization to act**. [#197](https://github.com/scowalt/machine-setup-scripts/issues/197) authorizes repository implementation; [ADR 0011](../adr/0011-scope-bb-server-customizations.md) requires separate live approval. Ordinary setup must leave the captured two-file Beelink state blocked. TMPDIR-only acceptance requires the reviewed #198 runtime change, not just this document or file retirement. Removing one blocker does not certify the remaining setup or deployment.

## 1. Authorize and establish prerequisites — no mutation

Obtain explicit owner approval naming the native Ubuntu account/machine, exact override, maintenance window, allowed interruption, backup location and recovery decision-maker. Arrange an independent operator connection: BB sessions may disconnect. Approval to inspect or retire a file is not approval to reload services, restart, rerun setup or reboot; agree those actions separately before proceeding.

Using only authorized read-only inspection:

- Verify the setup-managed app and ingress unit identities and reconcile their local files with systemd's exact loaded `FragmentPath`/`DropInPaths`. Record active/enabled states, app process identity/start time and saved endpoint privately. Inspect selected properties only, not full environments, credential files or unfiltered logs. Stop for unexpected overrides, conflicting identities, failed inspection or concurrent changes.
- Review `$HOME/.config/systemd/user/setup-bb-app.service.d/20-env-local.conf` itself, not just its filename: the expected setting is one `[Service]` section with only `EnvironmentFile=%h/.env.local`. Confirm its exact bytes and account ownership through verified real parent directories, rejecting links, multiple hard links and non-regular files. The captured file was `0664`; this procedure needs explicit approval to retire that reviewed group-writable file, not a runtime trust exception or permission repair. Changed content requires renewed review, not a dump to chat or logs.
- Preserve `10-tmpdir.conf`, its literal absolute-account-HOME `TMPDIR` assignment and the existing `$HOME/.cache/bb/tmp` tree. Verify the selected target and ancestors without creating, emptying or recursively inspecting its contents. Require the strict TMPDIR-only contract in the reviewed implementation; other locations/directives and unsafe paths remain blockers.
- Have the owner identify every required BB/provider setting and establish, through the installed version's supported **non-secret** native configuration metadata and source/precedence evidence, that it is configured independently of the broad override. Retain only setting/provider identifiers, configured-status results and the basis for that conclusion. Preserve `~/.env.local`, BB-native configuration and credentials; do not read/copy secret values, import an environment, authenticate to a provider or send a model request. If the native interface cannot establish this evidence, or any requirement is missing/uncertain, **stop before backup, removal or service changes** and request a separately scoped configuration review.

The historical diagnosis called the environment reference required. The running process predates both overrides; health `ok=true`, host `connected=true`, a credential file's existence or a provider name alone does not disprove that need or prove authentication. Loaded overrides describe manager configuration, not necessarily the current process.

## 2. Back up and retire only the reviewed file

Within the approved window, exclude concurrent setup, configuration edits and service changes. Revalidate the prerequisites immediately before mutation; inability to keep the reviewed identity/content stable is a stop condition.

Create a new account-owned private backup directory (`0700`) outside **all active systemd unit/drop-in search locations**, under verified real parents. Copy the reviewed override's exact bytes into an exclusively created regular backup (`0600`); record original ownership/mode, identity and a digest privately. Verify byte equality and backup identity without printing contents. Do not preserve the original group-write mode on the backup or put a `.bak`/hidden entry in the active drop-in directory.

Only after successful backup verification, recheck source and parent identity/content and remove exactly `20-env-local.conf` from the active directory. Preserve all other entries, native metadata, credentials, the account environment file and TMPDIR contents. Confirm the remaining local selection is exactly the reviewed TMPDIR override. Any discrepancy stops the procedure; do not widen removal or repair permissions. Record whether retirement occurred and where the verified backup resides.

## 3. Activate and verify — separate live authorization

File retirement alone does not reload systemd or replace the running process. At the agreed activation checkpoint, use a reviewed account-specific transition: stop ingress before the app, verify stopped states, then reload and verify configuration before authorizing startup. Account for automatic restart behavior and pending user-manager changes before `daemon-reload`; it can load changes beyond this unit. Recheck exact loaded fragments/drop-ins afterward: app TMPDIR only, no ingress overrides, no broad environment source. A mismatch blocks startup or setup, not a reason to repeat reload/restart blindly.

Authorize app startup knowing the generated `app-ready` hook automatically requests ingress after native readiness; there is no separate manual ingress approval gate inside that hook. Preserve the saved endpoint and unrelated routes; do not invoke ad hoc Tailscale Serve commands. A setup rerun needs its own approval because it updates packages and unrelated tools, not merely services.

For an authorized activation, verify the new managed process/start time, selected TMPDIR using a value-limited non-secret check, native readiness, ingress ownership and saved private endpoint. Remote browser/WebSocket access, local execution and boot continuity need their own scoped checks; provider authentication remains unverified here. Never dump the process environment. If setup was separately authorized, retain its actual final status and controlled diagnostics: a failed required operation remains an incomplete setup run, and rejected server readiness must still defer plugin refresh. Offline fixtures are not evidence of native continuity or live recovery.

## 4. Stop and recovery

On failure, retain the private backup and record only verified file, loaded-configuration and process states. Before activation, do not disturb a still-running old process merely to make the states match. After a failed transition, follow the approved stop/recovery plan and keep ingress from serving an unverified app; no repeated blind restarts.

Restoring the backup is **not automatic rollback**: it reintroduces unsupported account-wide credential inheritance, may affect the next start differently from the old process, and returns ordinary setup to refusal. Require fresh explicit approval for that exposure, revalidate backup/destination and absence of intervening edits, then separately approve any reload/start. Preserve the backup until the owner accepts recovery or migration. Never overwrite native credentials/configuration with old copies or import credentials to recover.

## Source boundaries

Read `setup_bb_server`, `bb_unit_preflight`, `bb_write_bb_guard`, `bb_config_merge_native`, `bb_restore_bb_services`, `run_setup_tasks` and `main` in [ubuntu.sh](../../ubuntu.sh) before adapting this procedure. The native-locked merge maintains `BB_APP_URL` and validates managed listener/data settings; it is not a provider configurator. Its failure can leave partial endpoint changes. Service restoration is best-effort, not a package/configuration or session-continuity rollback.

The [design evidence](2026-10-06-bb-server-customizations.md), [service-preflight fixtures](../../tests/test_bb_service_preflight.py), [diagnostic fixtures](../../tests/test_bb_server_diagnostics.py) and [lifecycle contract](../../tests/bb-server-contract.sh) bound the claims; neither historical diagnostic results nor this document establishes a completed migration.
