# Non-disruptive machine setup: agreed policy design

Status: the user approved design questions Q1–Q9 and the TASK-56 implementation plan, including argument-only maintenance authorization, data-only environment loading and the narrow default safe-write set. Implementation and isolated inert testing are in progress. Native continuity is not yet verified. No live setup, service changes, incident reproduction or rollout is authorized.

## Problem and evidence

Running setup can interrupt BB threads and other ongoing work. The current Ubuntu `setup_bb_server` function explicitly stops `setup-bb-ingress.service` and `setup-bb-app.service` before updating the package and starting the application again. The [current server documentation](../../README.md#opt-in-bb-server-on-native-ubuntu) acknowledges this disruption.

Other mutation paths extend beyond BB itself: blanket package upgrades, agent CLI/package updates, shared Node selection changes, full Chezmoi application, macOS Tailscale migration and Bazzite DNS repair. Protecting only the BB service does not protect the tools, configuration and connectivity its agents use.

These are source-level findings, not a diagnosis of a particular reported setup run. No live interruption was reproduced and no runtime non-disruption claim has been verified.

## Desired outcome

Ordinary setup preserves ongoing work and connectivity across all six entry points: `ubuntu.sh`, `mac.sh`, `pi.sh`, `bazzite.sh`, `wsl.sh` and `win.ps1`. It applies demonstrably non-disruptive changes, defers potentially disruptive work, and continues independent safe operations through log finalization.

The protected work includes BB turns and connections, idle sessions, terminals, development servers and other ongoing work—not only processes whose names identify them as agents. Shared machine resources can affect other accounts as well as the account running setup. A main-server change can affect remote users even when no agent process is visible locally.

“Non-disruptive” means avoiding setup-caused termination, session resets and connectivity loss. It does not promise zero CPU/disk contention or immunity from unrelated crashes, outages or independent updaters. Definitions live in [CONTEXT.md](../../CONTEXT.md).

## Agreed decisions

1. **Continuity is the default.** No safe-mode opt-in is required, on any supported platform.
2. **Defer rather than interrupt.** Pending changes remain visible and do not prevent independent safe work.
3. **Use conservative safety rules.** Apparent inactivity and absence of a recognized agent process do not establish safety. A new turn or subprocess may need the same resource immediately after inspection.
4. **Accept delayed freshness.** Potentially disruptive changes, including security updates, can remain pending until maintenance. The summary must make that trade-off visible.
5. **Maintenance requires separate, per-run authorization.** It happens during a window chosen by the user and is invoked outside BB. No saved permission in `.env.local`, automatic idle-time application or background restart is introduced.
6. **Distinguish deferral from failure.** Policy-authorized deferrals alone are successful execution of the safe policy, not proof of full convergence. Actual operation failures and failed safety inspections still produce a nonzero result after independent work and log finalization.
7. **Do not take over independent updaters.** Preserve existing OS/app automatic-update policy. Ordinary setup must not newly enable potentially disruptive background updaters as a way of completing deferred work later.
8. **No first-run exemption.** Installing a missing package can mutate shared dependencies or restart services. Full first-time provisioning may require maintenance; isolated, demonstrably safe installation can still proceed normally.
9. **Do not repair outages disruptively by default.** Report failed health checks without restarting existing components or repairing shared networking. Continue independent safe work and reserve disruptive recovery for maintenance.

## Safety boundary

The policy must cover actual effects and indirect prerequisites, not just top-level operation names. In particular:

- BB server, ingress, machine daemon and desktop lifecycle and installation changes.
- Shared runtimes, package prefixes, agent executables, extensions, skills and configuration that ongoing work can read or execute later.
- System package operations, dependency upgrades, installer hooks, cleanup and removal of existing files.
- Chezmoi initialization with apply, update-and-apply, full apply and targeted repairs. A files-only change is not automatically safe: a running consumer may read it later or reload it immediately.
- Network, DNS, Tailscale, service, permission and authentication configuration changes that can affect existing work.
- Scheduled or newly enabled background work caused by setup, not just synchronous commands.

Do not substitute a one-time busy-process check for this boundary. Classify an operation by its complete effects. If those effects cannot be established as non-disruptive, defer the operation rather than guessing. Where an otherwise eligible operation requires an inspection that fails, record an inspection failure rather than disguising it as an intentional deferral.

The boundary applies before the earliest mutation, including bootstrap paths and helpers called by multiple consumers. It cannot depend on successfully updating Node, Pi or BB first. Deferred prerequisites defer their dependent operations; they must not be silently provisioned through another caller. Unrelated safe work still runs.

Preserving BB through `BB_SERVER=0` alone is not sufficient: the rest of setup can still affect shared resources. Existing BB role/platform gates remain separate from the non-disruption policy.

## Maintenance boundary

Maintenance authorization permits potentially disruptive setup changes for that invocation. It does not waive ownership, symlink, credential, package-policy, readiness or supported-platform checks. It does not authorize new BB enrollment, authentication, unrelated service takeover or remote fleet changes.

Maintenance must preserve existing data, recovery behavior and failure aggregation. It does not add automatic reboots. It is not permission to execute an unchecked list of stale commands: the implementation should reevaluate desired state and prerequisites when maintenance is actually requested.

The approved command-line interface is `--maintenance` on Bash and `-Maintenance` on PowerShell: deliberate per-invocation authorization, never an environment-file bypass. Known BB context markers refuse it without a force override. Documentation directs maintenance to a separate terminal outside BB and warns that absent markers do not prove other work is absent. The implementation and offline validation evidence is tracked in [TASK-56 validation](../research/2026-09-29-non-disruptive-validation.md); native continuity remains separate rollout work.

## Results and diagnostics

Keep the following outcomes distinct:

| Outcome | Meaning |
| --- | --- |
| Verified current | The relevant desired state was inspected and established without disruptive changes. |
| Applied | An authorized change completed and its required result was verified. |
| Deferred | Policy prevented an operation; no completed update or verified desired state is implied. |
| Failed | An attempted operation, required inspection or required verification failed. |

A run with safe work completed and only policy deferrals should report **“safe work completed; maintenance pending”** and return success. It must not report that the machine or all tools are up to date. If update discovery itself was deferred, say that availability was not checked rather than inventing an available version.

List deferred operations or bounded operation groups, the reason for deferral and affected dependent work. Reuse normal run logs and finalization. Keep diagnostics controlled and secret-safe: no credential values, raw process arguments, service contents or arbitrary exception output.

Failed health checks remain failures even if no repair was attempted. Both failures and pending maintenance must remain visible when they occur together.

## Verification criteria for implementation

Use extracted real helpers and actual callers with temporary homes, synthetic dotfiles and inert package/service/network commands. Do not run live setup, execute BB or installed skills/extensions, restart services, change Tailscale or contact other machines to validate development changes.

Required evidence:

1. Default invocations of all six scripts reach the protection before early mutations; unsupported/headless platform rejection still occurs at its existing required boundary.
2. A running BB fixture retains its app, ingress, daemon, endpoint, package files and configuration. No stop/restart or in-place update escapes through direct or indirect callers.
3. Protected shared-runtime, agent-package, dotfile and network fixtures remain unchanged when their operations are deferred. Safe independent operations and final log handling still execute.
4. Idle sessions, unrecognized consumers and work appearing after an initial observation do not authorize a disruptive operation. Tests must not equate an empty process list with safety.
5. First-time installation with disruptive dependency/hooks is deferred; explicitly classified non-disruptive installation can proceed. Existing unhealthy services are reported without disruptive repair.
6. Policy deferral propagates through dependent operations without converting it into a false installation failure or claiming readiness. Actual inspection, mutation and verification failures remain nonzero.
7. Existing automatic-updater settings are preserved; ordinary setup does not enable new disruptive background work.
8. Maintenance authorization is per-invocation, cannot be restored by loading `.env.local`, and does not bypass existing trust/security/platform guards. Existing stopped-update and recovery behavior is tested only through inert fixtures.
9. Summary and exit-status tests distinguish current, applied, deferred and failed outcomes, including mixed results and unqueried update availability.
10. Repeated runs preserve these properties, and shared embedded helpers remain identical where required.

A regression must exercise the real caller path and assert forbidden commands and protected-state changes, not merely find a guard string in source. Fixture wrappers should reject unexpected mutation commands so a newly introduced path cannot silently escape coverage.

Run the affected BB server/preparation/desktop, reliability, headless, shared-runtime, Pi package/profile/Go, managed-skill, OpenCode, Homebrew/CLT, weekly and reboot contracts, including available PowerShell fixtures. Add the cross-platform non-disruption contract; run syntax, ShellCheck and documentation checks. Report missing native-platform coverage honestly. Separately authorized native rollout must verify actual continuity of BB turns, connections and representative other work; offline fixtures alone do not prove that outcome.

## Implementation and rollout boundaries

- Prepare and obtain approval for an implementation plan before changing setup behavior.
- Inventory all mutation paths and reconcile affected existing contracts; a BB-only patch must not be presented as the complete cross-platform guarantee.
- Update setup-script versions, README behavior/recovery guidance and relevant repository instructions when the implementation changes their existing policies. Do not silently weaken security or reinterpret a failed operation as success.
- Keep independent OS/app/dotfile updaters outside setup's ownership and document that limitation.
- No live setup, service repair, fleet operation, package update or interruption is authorized by approval of this design alone.
