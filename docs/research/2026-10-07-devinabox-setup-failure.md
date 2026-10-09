# Devinabox Ubuntu setup v311: APT recovery and blocked BB maintenance

**Historical diagnosis, not current maintenance prerequisites.** [ADR 0012](../adr/0012-accept-account-owned-ordinary-directories.md) supersedes the ordinary-directory refusals described below; [spec #221](https://github.com/scowalt/machine-setup-scripts/issues/221) and [ADR 0013](../adr/0013-preserve-reviewed-bb-environment-inheritance.md) supersede retirement-first refusal for the recognized existing app environment references. Original observations, uncertainty and consumed query approval remain unchanged. The configuration-review/retirement next steps below are historical for that preserved-reference path; this annotation supplies no new native evidence, live authorization or completed migration claim.

## Conclusion and evidence boundary

The uploaded run has **two independent required-operation failures**: HTTP 404 fetching two librsvg security archives, and BB's local service-drop-in preflight refusal. Later independent successes do not erase either failure from that run. Subsequent native evidence establishes that **both packages were upgraded afterward and BB's app/ingress are currently running**, with positive local app/host health checks. The BB customization blocker remains present. This is not evidence that BB went down, nor a completed setup or provider-readiness verification. [Log L60–72, L212–219, L274][log]; [native follow-up][native]; [setup caller][ubuntu].

**Least disruptive next step:** preserve the running deployment, account environment file and credentials; request a narrowly scoped, separately authorized review of **devinabox / scowalt / `setup-bb-app.service.d/env.conf`** and supported independent sources for all required provider/agent-tool inputs, including non-secret inherited inputs of unauthenticated capabilities. Do not switch mirrors immediately, blindly chmod/remove/rename the override, reload/restart, rerun whole setup or reboot to clear this diagnosis. Whole-file environment inheritance is deliberately unsupported, and the existing migration document does not authorize this differently named override. [Native follow-up][native]; [ADR 0011][adr]; [migration prerequisites][migration]; [ordinary-setup disruption boundary][rollback].

Evidence categories used below:

- **Logged facts:** the parent's authenticated, ANSI-stripped, 275-line redacted copy of [collector object `2026-10-07-03-22-09-069.log`][collector]. It records Ubuntu version 311 and local filename `/home/scowalt/.local/log/machine-setup/2026-10-06-232112.log`; upload time is not the local run filename. [L1–5, L275][log]; [initial evidence][initial].
- **Current native observations:** the parent's bounded read-only follow-up on devinabox, approximately 12:03–12:08 UTC on October 7. These supersede earlier current-state conclusions, not historical log facts. This research worker did not inspect the host. [Native follow-up][native].
- **Demonstrated mechanisms:** repository source at `be7cea1dccb9bd90a2baab392e393a3fc897ad5c`, whose Ubuntu banner matches the log; parent-reported contained differential fixtures; official APT/systemd documentation. Ubuntu's relevant last change is `4af2e2df5f57e9740072760384f3beb895995dd7`. [Source][ubuntu]; [initial fixture evidence][initial].
- **Public verification:** this worker read both package indexes and made archive **HEAD** requests at approximately 12:05 UTC. No package body was downloaded or executed, and no APT operation or signature verification was performed.

## 1. APT: historical archive inconsistency, subsequently recovered

### What failed

The run refreshed indexes, then selected seven upgrades. Fetches of `librsvg2-common` and `librsvg2-2`, both amd64 version `2.58.0+dfsg-1ubuntu0.1`, returned 404 from Hetzner's `noble-security/main` archive at IPv6 address `2a01:4ff:ff00::3:3`. Five other archives were fetched, but the log does not show this transaction installing them. APT reported unavailable archives; setup released its temporary tmux hold and reported `Package upgrade failed`. No successful upgrade retry appears in this uploaded run. [L20–72][log].

APT's `update` resynchronizes **index files**; `upgrade` subsequently retrieves and installs selected packages. Therefore a successful index refresh is not proof that the corresponding archive files are retrievable. Setup follows those distinct phases in `update_dependencies`, retains the upgrade failure, and returns before its later autoremove step. [Official `apt-get` description][apt-get]; [Ubuntu package-management guide][ubuntu-packages]; [`update_dependencies`, lines 628–679][ubuntu].

### Index versus artifact evidence

The parent's earlier GET probes independently reproduced both Hetzner 404s while Hetzner and official Ubuntu indexes advertised the same versions, archive paths and SHA256 values. Official Ubuntu archive GETs returned 200; changing `%2b` to literal `+` did not resolve Hetzner's refusal then. This supports **index/archive availability inconsistency at the observed mirror endpoint**, rather than requiring an obsolete local index or plus-encoding explanation. It does not identify Hetzner's internal synchronization, caching or maintenance cause. [Initial evidence][initial]; [logged exact requests L68–69][log].

At this worker's approximately **12:05 UTC** public recheck, both indexes still advertised identical selected records:

| Package, amd64 | Version | Size, bytes | SHA256 advertised by both indexes |
| --- | --- | --- | --- |
| `librsvg2-2` | `2.58.0+dfsg-1ubuntu0.1` | 2140940 | `47aa51a12ecc102b6dc867fe34319fcf6fa590c44bd8a3e22a2c473f3b8dd875` |
| `librsvg2-common` | `2.58.0+dfsg-1ubuntu0.1` | 11788 | `e9d3f20d5113d4b4cbeb2834d15d2bdc4b5bacb0767b743380e7afcd91ec7415` |

Primary indexes: [Hetzner][hetzner-index] and [Ubuntu security][ubuntu-index]. Their `Filename` fields are respectively `pool/main/libr/librsvg/librsvg2-2_2.58.0+dfsg-1ubuntu0.1_amd64.deb` and `pool/main/libr/librsvg/librsvg2-common_2.58.0+dfsg-1ubuntu0.1_amd64.deb`.

Both exact encoded-plus [Hetzner librsvg2-2][hetzner-lib] and [Hetzner librsvg2-common][hetzner-common] HEAD requests now returned **200**, including forced IPv6 requests to the originally logged address and IPv4 requests to `185.12.64.3`. Literal-plus Hetzner requests and both forms at official Ubuntu also returned 200; reported lengths matched the index sizes. This is response/metadata evidence, **not downloaded-byte hash verification**. [Official Ubuntu librsvg2-2][ubuntu-lib]; [official Ubuntu librsvg2-common][ubuntu-common].

Package checksums belong in the Packages index; signed Release metadata authenticates those indexes, and APT verifies the chain. Matching public records or HTTP 200 alone does not replace that validation. Preserve normal repository signature/hash verification in any future authorized APT work. `--fix-missing` can hold back unavailable packages; it is not proof that the required upgrades completed. [Official `apt-secure`, “Signed repositories”][apt-secure]; [official `apt-get`, `--fix-missing`][apt-get].

### What is now recovered

The parent's later native queries report both packages **installed (`ii`) at the formerly failing version**, matching their current candidates, with the selected security source still Hetzner. Narrow dpkg-log parsing records both upgrades from `2.58.0+dfsg-1build1`, and both installed-state entries, at **October 7, 06:59:33 local**. Fresh native GETs of both exact formerly failing URLs returned 200. The upgrader's identity was not established; neither investigation performed the upgrade. [Native APT follow-up][native].

Thus the two named archive/package symptoms recovered **after** the failed run. There is no immediate evidence-based need to edit APT sources or retry their installation. This does not certify every originally selected upgrade, all current security updates, or a subsequent complete setup run. Mirror internals and precise restoration time remain unknown. [Historical upgrade selection L52–70][log]; [native follow-up][native].

## 2. BB: the local trust gate rejects existing customization

### Logged failure and sufficient mechanism

The controlled diagnostic is `[preflight.unit-dropins]` for `$HOME/.config/systemd/user/setup-bb-app.service.d`, followed by `BB server setup incomplete`. The caller subsequently invokes plugin refresh in `block-default` mode and retains its earlier error through independent work and log finalization. [L212–219, L274–275][log]; [`setup_bb_server` and `run_setup_tasks`][ubuntu]; [refresh wrapper][refresh].

Initial inspection and the **12:06 UTC revalidation** agree on the unsafe metadata shape: an account-owned, real **0775** drop-in directory containing one account-owned, single-linked, regular **0664** file. The follow-up identifies that sole file as `env.conf`. Initial inspection recorded 40 bytes and September 30 ctime/mtime, predating the uploaded run. Bounded stable classification confirmed only a service-level whole-account `~/.env.local` EnvironmentFile reference, not TMPDIR. No `~/.env.local` contents or credentials were read. Current metadata supports the explanation but is not a historical filesystem snapshot. [Initial metadata evidence][initial]; [native revalidation][native].

The **directory's group-write bit alone is sufficient** for the exact refusal:

1. `bb_owned_safe_directory` rejects account-owned directories when `(mode & 022) != 0`; 0775 satisfies that rejection.
2. `bb_unit_dropins_empty` returns failure **before enumerating entries** when that check fails.
3. Version 311's `bb_unit_dropins_snapshot` permits TMPDIR review only after the distinct status **2** meaning “safely inspected, nonempty.” An inspection/trust failure remains failure.
4. `setup_bb_server` returns at this local snapshot gate, **before** `bb_unit_preflight` queries systemd's loaded selection or any BB lifecycle/package/configuration operation. This failure path does not establish that the service is stopped. [Source: `bb_owned_safe_directory` at line 8838, `bb_unit_dropins_empty` at 9084, `bb_unit_dropins_snapshot` at 9183, and the caller at 9585–9612][ubuntu].

The parent's real-helper/caller differential replay corroborates the mechanism: populated **and empty 0775** directories reproduce the refusal; an **empty 0755** control reaches the next inert gate (sentinel status 73); a **nonempty 0700** directory with an unreviewed entry remains rejected. Status 73 is not native setup success. The parent reports 9 containment/extraction, 8 setup-default/environment and 21 BB-preflight methods passing, with the diagnostic entry intentionally red; artifacts are `/tmp/setup-fixture-matrix-1odi1h13` and `/tmp/setup-fixture-matrix-jnkv5550`. This worker did not rerun tests. [Initial fixture evidence][initial]; [existing preflight contracts][preflight-tests]; [audited execution boundary][audit].

### Why chmod alone is insufficient

Clearing group write would only remove the first blocker. Nonempty app directories must still meet the exact reviewed **0700 directory / 0600 `10-tmpdir.conf` / narrowly allowed TMPDIR content and target / exact loaded selection** contract. `env.conf` is not that reviewed file, and its whole-file EnvironmentFile directive remains outside supported customization even if its permissions were made private. Neither renaming it nor changing modes converts environment inheritance into a TMPDIR-only override. This is intentional policy, not a demonstrated repository defect or permission-repair instruction. [Source `bb_tmpdir_snapshot` and `bb_unit_preflight`][ubuntu]; [ADR 0011][adr]; [customization decision Q2–Q6][design].

### Current service observations, not recovery claims

At **12:03 UTC**, the parent observed app and ingress **active/running**, correct setup unit fragments, `Result=success` and `NeedDaemonReload=no`. The app's loaded drop-in is exactly `setup-bb-app.service.d/env.conf`; its selected EnvironmentFiles property references the account environment file with `ignore_errors=no`. Ingress has no selected drop-ins. App process start was October 5, 11:16:09 EDT; ingress start was October 6, 21:29:25 EDT, both before the failed setup run. At **12:06 UTC**, local `/health` returned HTTP 200 with `ok=true` and a nonempty launch ID; local host `/status` returned HTTP 200 with `connected=true`, matching known host identity and local app URL. [Native properties and bounded health observations][native].

These are positive **current local service/health observations**, not evidence of a BB outage and subsequent recovery. Setup trust preflight remains blocked; provider authentication, remote browser/WebSocket access and restart/boot/session continuity were not tested. A credential file's existence, host connection or provider name would not establish provider configuration source, precedence or authentication. [Native scope][native]; [ADR 0011][adr]; [migration evidence requirements][migration].

Systemd distinctions matter:

- `.conf` drop-ins supplement the main unit; different filenames do not make equivalent EnvironmentFile directives harmless. `%h` resolves to the home of the user running the service manager. [Official `systemd.unit`, drop-ins and specifiers][systemd-unit].
- `EnvironmentFile=` reads variable assignments shortly **before process execution**; its values override `Environment=` assignments, with later environment files winning conflicts. It is not a selective BB/provider import. Systemd warns that environment variables are unsuitable for passing secrets. No claim is made about which actual values this running process inherited. [Official `systemd.exec`, “Environment”][systemd-exec].
- `systemctl show` exposes both manager configuration and runtime properties; `FragmentPath` identifies the read unit source. Disk files, manager-loaded configuration and an already-running process are distinct evidence surfaces. `daemon-reload` reloads unit configuration/generators/dependencies; `restart` stops and starts units. Loaded paths or `NeedDaemonReload=no` do not attest the process's credential values or provider readiness, and reload is not an innocuous substitute for an approved activation plan. [Official `systemctl`, `show`, `cat`, `daemon-reload`, `restart`][systemctl]; [systemd D-Bus properties][systemd-api]; [migration activation boundary][migration].

## 3. Symptom disposition

| Symptom | Evidence-based classification |
| --- | --- |
| APT `Ign` index messages | Recovered **within the run** with corresponding `Get` entries; distinct from later archive 404s. [L29–43][log]. |
| Two librsvg archive failures | Not recovered in the uploaded run; both URLs available and both packages installed **afterward**. [L60–72][log]; [native follow-up][native]. |
| Temporary tmux hold | Released after the failed fetch transaction. [L47, L71][log]. |
| BB preflight rejection | Still explained by current 0775 directory and unsupported `env.conf`; running services do not clear it. [L212–214][log]; [native revalidation][native]; [source][ubuntu]. |
| BB plugin-refresh deferral / “No verified local …” | Downstream safety behavior, not a completed refresh or proof that BB is absent/down. [L218–219][log]; [caller][ubuntu]; [refresh wrapper][refresh]. |
| npm deprecation warning | Followed by successful Pi installation and package refresh; not a separate logged required-operation failure. [L233–262][log]. |
| `HEADLESS=1` desktop skip | Intentional exclusion, applications left untouched. [L108][log]. |
| Pending reboot | Advisory about already-applied updates; not proof reboot fixes either historical failure. The listed kernel packages do not explain the archive/drop-in refusals. [L268–272][log]; [reboot detector and failure paths][ubuntu]. |
| Final “completed with errors” | Correct incomplete-run classification. The uploaded log does not print a numeric final exit status; source aggregates failures and finalizes logging. [L274–275][log]; [`run_setup_tasks` / `main`][ubuntu]; [glossary][glossary]. |

## 4. Narrow next action and stop conditions

1. **No immediate APT remediation:** preserve the now-working security source and normal authentication policy. If this exact fetch problem recurs, recheck index/archive consistency before considering an owner-approved, security-source-only change; do not disable verification or treat held-back updates as success. [Native recovery][native]; [APT authentication][apt-secure]; [`--fix-missing`][apt-get].
2. **Seek configuration-review approval, not an outage repair:** name devinabox, scowalt and the exact `env.conf`. Have the owner identify all enabled/configured provider and agent-tool capabilities, whether authenticated or unauthenticated, required inputs (including non-secret inherited inputs) and explicit exclusions, then establish supported, non-secret native configuration/source/precedence evidence independent of the broad override. Current health does not meet that prerequisite. If any requirement is missing or uncertain, stop without reading/copying credentials, importing `~/.env.local`, deleting the override or disturbing the running services. [ADR 0011][adr]; [migration section 1][migration].
3. **Any transition needs its own exact approval:** the documented retirement of Beelink's `20-env-local.conf` is a bounded procedure, not permission to retire devinabox's `env.conf`. Adapt/review the actual filename, content/identity, unsafe directory/file modes, private verified backup outside active systemd search locations, interruption and recovery plan. Preserve native credentials, account environment file and unrelated state. Removal, reload/start/restart, setup rerun and reboot require separately agreed scope; none is authorized by this note. Ordinary setup can update unrelated packages/tools and interrupt work, so it is not the minimal review step. [Migration sections 1–4][migration]; [ADR 0011][adr]; [rollback scope][rollback].

The original diagnosis research worker performed no implementation change, commit, issue action, live setup, application/plugin load or native remediation. Parent-reported tests are offline mechanism evidence, not rollout or continuity evidence; the earlier fixture incident's uncertainty is unchanged. Public indexes/URLs are mutable, and the investigation did not verify downloaded artifact hashes, identify the later upgrader, reconstruct historical process environments, or establish provider/browser/restart/boot readiness. [Parent evidence][initial]; [native scope][native]; [fixture audit][audit]; [incident record][incident].

## 5. Native configuration audit and the consumed query exception

This section is **existing-evidence synthesis for [#205](https://github.com/scowalt/machine-setup-scripts/issues/205)**, not an additional investigation or updated host snapshot. The [private bounded-audit report][native-audit] and [filtered one-query result][native-inventory] are supplementary, ephemeral records. The facts and limitations needed for the blocker are retained here and in the [devinabox evidence/operator packet][devinabox-packet]; understanding the stop condition does not require those private files.

### Static findings — supported mechanisms, not configured inventory

The reviewed installed application was **`bb-app` 0.44.0**. Official [configuration documentation][bb-config-doc] was pinned to upstream `68a1e8b7aa84fbd836eb8825e4d042ae0c52e74a`, not proven byte-identical to that installed release. Prior research read static help/schema/registration and selected installed code only; it did not execute/import installed BB or establish account-specific provider/tool selections.

| Existing static evidence | What it establishes / what remains unknown |
| --- | --- |
| Launcher (`dist/bb-app.js`, runtime/configuration dispatch) | Managed configuration commands reject secret-shaped keys for their display, but runtime resolution loads managed configuration **and managed env files before dispatch**. A non-secret display is not a no-secret-read path. Generic merge order is base/option environment → managed configuration → managed env, with a final bind-host override; `BB_SERVER_URL` uses explicit option → persisted `serverUrl` → environment → default. Neither order identifies this account's selected sources for all required keys. |
| Server configuration and provider status (`server/dist/start-server.js`, `serverAccessStatus`, `getProviderState`) | `/system/config` can call access-provider `availability()`; provider state can issue `provider.health` host maintenance requests and use contributed-environment health. These are not inert stored-metadata views. No live status/configuration request was approved by this static review. |
| Provider models/usage and plugin settings | Catalogs can refresh in the background; inspected usage paths can collect stale/absent observations even with `refresh=false`. Synchronous settings storage skips secret descriptors, asynchronous storage reads secret files, and the complete public settings route was not proven safe. A masked response or “no refresh” label does not establish the full path's effects. |
| Provider declarations | Codex/Claude Code bundles were examples, not an exhaustive provider audit or configured identities. Claude Code's declared `CLAUDE_CODE_OAUTH_TOKEN` passthrough demonstrates possible inherited provider input, **not** its use on devinabox. Defaults, registrations and installation cannot enumerate required workflows. |
| Contribution resolution (`resolveHostEnvironment`, `mergeHostAndProviderEnvironment`) | Static order is built-in Git → global machine environment → project environment, then plugin-provided provider contributions at thread launch, with later names winning. Git resolution can execute credential/authenticated subprocesses. Full host bridge, each provider's spawn/import behavior and final child-tool inheritance were not traced. This is not a complete effective-source/independence report. |

Keep three categories separate: **server/launcher settings**, **provider authentication/settings/contributions**, and **child-tool inputs**. Native configuration can be a scoped source without proving it wins every required input, or that every launched tool receives it. A setting name, credential-file existence, provider readiness label or current host health cannot fill source/precedence gaps. Missing native configuration would need separate scoped review/provisioning, not an account dotenv importer or new credential store. [ADR 0011][adr]; [devinabox packet][devinabox-packet].

### Bounded follow-up trace — why one names view needed extra permission

The existing follow-up stopped after six targeted code reads plus symbol/locator searches in the already identified installed `server/dist/start-server.js`. It traced:

1. `publicApiRoutes.system.machineEnvironment` (**L44801–44806**) and handler (**L177753–177756**): GET `/settings/machine-environment`, no request switch to suppress Git health.
2. `machineEnvironmentView` (**L66829–66849**) → `readMachineEnvironment` (**L66748–66750**): default global scope (`projectId = null`), reading/parsing encrypted stored rows, then mapping names/notes with `value: null`. This is not a metadata-column-only database read, but the traced row mapping calls neither decryption nor encryption-key acquisition.
3. `getAppSettings` (**L27953–27979**) and `machineGitHealth` / `resolveGitCredentials` (**L66438–66494**): unless a **global** `GH_TOKEN` row exists or automatic Git credentials are disabled, `execFile` runs `gh auth token --hostname github.com`, then on successful token parsing `gh api --hostname github.com user`. A project-local `GH_TOKEN` does not suppress this global path; the project view calls it first.

Within that traced GET chain, no explicit DB write, plugin/provider callback, catalog refresh or environment-key creation was found. Nearby mutation routes are distinct. **General request middleware and Git internals were not exhaustively audited**, so no universal no-effects claim follows. Normal request authentication is distinct from the handler's additional token acquisition/authenticated GitHub request. The original strict metadata-only permission did not cover that additional behavior. [Private detailed trace][native-audit].

### Later approved observation — limited result and exhausted permission

Scott subsequently approved **one** local devinabox global inventory request, including its built-in use of existing GitHub credentials, with only variable names and controlled status fields exposed. At **2026-10-07 15:16:39 UTC**, the approved `bb machine env list --json` request returned:

| Approved retained field | Result |
| --- | --- |
| Addressed scope | Local devinabox server, global native machine-environment records |
| Variable names | Empty list: **zero global records** |
| Built-in Git status | **`logged in`** |
| Values, notes, raw response/arbitrary diagnostics disclosed | **No**; schema-filtered output only |

No live query was performed by the static research worker; this separately approved follow-up is later evidence. It did not authorize credential/configuration changes, provider inference, project/provider queries, service actions or setup. **That one-query exception is consumed**, not renewable by this packet, issue label or repository implementation request.

Crucially, `runGh` inherits the current service environment; the successful Git result does not identify whether its credential depends on the broad override. Zero global records do not mean zero requirements, no project/provider records, no enabled/configured child-tool capabilities (authenticated or unauthenticated), or independent provider/tool configuration. The observation did not establish usable/decryptable native secrets or complete launch precedence. Do not manufacture configured identities from the inspected declarations.

### Durable stop condition and next input

The unresolved requirements are the complete enabled/configured provider and agent-tool inventory, including unauthenticated capabilities with non-secret inherited inputs, owner exclusions, selected supported per-workflow sources/precedence independent of `env.conf`, fresh baselines and exact bounded acceptance requests/costs. No pre-existing integration failure inventory was established; unknown is not passed. Failures must stay separate and block transition when they prevent the required proof.

The smallest next input is Scott's non-secret list of all actually enabled/configured provider and agent-tool capabilities, whether authenticated or unauthenticated, purposes/scopes and exclusions, with existing source-evidence references for required inputs, including non-secret inherited inputs. If a specific row still needs a native view/probe, its complete effects and scope require a **new separate review/authorization**; credential-use approval is additionally required where relevant, and lack of authentication waives no other authorization. Unavailable safe evidence is a blocker, not permission for raw credential/process-environment reads or an expanding upstream audit/inspector. [#207](https://github.com/scowalt/machine-setup-scripts/issues/207) remains blocked before backup, retirement, directory handling or service changes. The exact `env.conf` and unsafe containing directory, approval stages, saved endpoint, independent controller and fresh restoration decision are covered by the [devinabox packet][devinabox-packet]. The [Beelink procedure][migration] is not devinabox authority. No live inspection, migration, policy change or new behavioral execution occurred for this documentation synthesis.

## Sources

- Operational evidence: [redacted collector log][log], [initial parent findings][initial] and [final native follow-up][native]. The [canonical collector object][collector] requires authenticated access and was not refetched here.
- Existing configuration evidence: [durably summarized static report][native-audit], [filtered approved query result][native-inventory] and [devinabox operator packet][devinabox-packet]. Private `/tmp` records are supplementary, not a complete inventory or prerequisites to understanding the blocker.
- Repository policy/mechanism: [Ubuntu source][ubuntu], [refresh wrapper][refresh], [service-preflight fixtures][preflight-tests], [ADR 0011][adr], [customization decision][design] and [separate migration procedure][migration].
- External primary sources already consulted: [pinned BB configuration documentation][bb-config-doc], Ubuntu's [`apt-get`][apt-get] and [`apt-secure`][apt-secure] manuals, [package-management documentation][ubuntu-packages], [Noble systemd unit][systemd-unit]/[execution][systemd-exec]/[control][systemctl] manuals, [upstream systemd API][systemd-api], and the [Hetzner][hetzner-index]/[official Ubuntu][ubuntu-index] package indexes and linked archive URLs. None was refetched for #205.

[collector]: https://logs.scowalt.com/logs/devinabox/2026-10-07-03-22-09-069.log
[log]: /tmp/setup-diagnosis-devinabox-6XGdq3Pz/collector.redacted.log
[initial]: /tmp/setup-diagnosis-devinabox-6XGdq3Pz/findings.md
[native]: /tmp/setup-diagnosis-devinabox-6XGdq3Pz/live-followup.md
[native-audit]: /tmp/setup-diagnosis-devinabox-6XGdq3Pz/native-config-evidence-research.md
[native-inventory]: /tmp/setup-diagnosis-devinabox-6XGdq3Pz/approved-native-inventory.json
[devinabox-packet]: ../plans/2026-10-07-devinabox-bb-environment-migration.md
[bb-config-doc]: https://github.com/get-bb/bb/blob/68a1e8b7aa84fbd836eb8825e4d042ae0c52e74a/docs/configuration.md
[ubuntu]: ../../ubuntu.sh
[refresh]: ../../lib/bb-plugin-refresh.bash
[preflight-tests]: ../../tests/test_bb_service_preflight.py
[adr]: ../adr/0011-scope-bb-server-customizations.md
[migration]: ../plans/2026-10-06-bb-environment-override-migration.md
[design]: ../plans/2026-10-06-bb-server-customizations.md
[rollback]: 2026-09-30-setup-rollback.md
[glossary]: ../../GLOSSARY.md
[audit]: 2026-09-29-fixture-execution-audit.md
[incident]: 2026-09-29-fixture-containment-incident.md
[apt-get]: https://manpages.ubuntu.com/manpages/noble/en/man8/apt-get.8.html
[apt-secure]: https://manpages.ubuntu.com/manpages/noble/en/man8/apt-secure.8.html
[ubuntu-packages]: https://documentation.ubuntu.com/server/how-to/software/package-management/
[hetzner-index]: https://mirror.hetzner.com/ubuntu/security/dists/noble-security/main/binary-amd64/Packages.xz
[ubuntu-index]: https://security.ubuntu.com/ubuntu/dists/noble-security/main/binary-amd64/Packages.xz
[hetzner-lib]: https://mirror.hetzner.com/ubuntu/security/pool/main/libr/librsvg/librsvg2-2_2.58.0%2bdfsg-1ubuntu0.1_amd64.deb
[hetzner-common]: https://mirror.hetzner.com/ubuntu/security/pool/main/libr/librsvg/librsvg2-common_2.58.0%2bdfsg-1ubuntu0.1_amd64.deb
[ubuntu-lib]: https://security.ubuntu.com/ubuntu/pool/main/libr/librsvg/librsvg2-2_2.58.0%2bdfsg-1ubuntu0.1_amd64.deb
[ubuntu-common]: https://security.ubuntu.com/ubuntu/pool/main/libr/librsvg/librsvg2-common_2.58.0%2bdfsg-1ubuntu0.1_amd64.deb
[systemd-unit]: https://manpages.ubuntu.com/manpages/noble/en/man5/systemd.unit.5.html
[systemd-exec]: https://manpages.ubuntu.com/manpages/noble/en/man5/systemd.exec.5.html
[systemctl]: https://manpages.ubuntu.com/manpages/noble/en/man1/systemctl.1.html
[systemd-api]: https://www.freedesktop.org/software/systemd/man/255/org.freedesktop.systemd1.html

The collector requires authenticated access; it was retrieved by the parent, not refetched here. `/tmp` links are private, ephemeral evidence references, not committed attachments. Repository links refer to the reviewed source revision above. Official documentation and package metadata were consulted on October 7, 2026.
