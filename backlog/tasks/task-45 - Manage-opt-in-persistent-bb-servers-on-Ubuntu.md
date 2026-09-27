---
id: TASK-45
title: Manage opt-in persistent bb servers on Ubuntu
status: Done
assignee:
  - '@pi-luna'
created_date: '2026-09-27 16:40'
updated_date: '2026-09-27 21:54'
labels:
  - setup
  - bb
  - ubuntu
dependencies: []
references:
  - ubuntu.sh
  - README.md
  - CONTEXT.md
  - tests/setup-reliability-contract.sh
  - tests/headless-paseo-daemon-contract.sh
  - tests/shared-node-runtime-contract.sh
  - >-
    https://github.com/get-bb/bb/blob/4354b88ce14457fbdf1fc1a8e0db2dd4b5ef90f3/packages/bb-app/README.md
  - >-
    https://github.com/get-bb/bb/blob/4354b88ce14457fbdf1fc1a8e0db2dd4b5ef90f3/docs/multiple-devices.md
  - 'https://tailscale.com/docs/reference/tailscale-cli/serve'
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Install and maintain independent stable bb agentic IDE servers through opt-in Ubuntu setup runs. BB_SERVER=1 enables management; unset/0 skips without stopping or deleting existing deployments; other nonempty values fail. A nonempty process value overrides ~/.env.local. Intended initial opt-ins are devinabox and scott-beelink-ubuntu, but hostnames never determine eligibility. No live fleet changes during development.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Selected hosts install or update the official stable bb-app package using the existing compatible shared Node runtime and native npm without changing global npm/Socket policy, project pins, shell profiles, provider credentials or existing bb project/session data. Installation and native-artifact verification failures propagate.
- [x] #2 Setup manages a dedicated account-level systemd service and verified lingering so the full bb launcher and local execution daemon start without login, survive logout and recover from crashes. BB stays on loopback, uses its own existing account credentials, and does not use an in-app updater or enrolled-remote-host topology.
- [x] #3 Production ingress uses an explicitly managed persistent per-node Tailscale HTTPS endpoint with a port chosen once and retained across reruns/reboots; BB_APP_URL matches that fixed origin. Preserve existing Serve routes, Portless proxy/apps, unrelated services and existing tailnet access controls; add no extra login, public exposure, Funnel, relay, blanket reset or route takeover.
- [x] #4 Setup may interrupt owned BB work to apply stable updates; preserve unmanaged installations/services and fail rather than take them over. Reruns do not duplicate services/routes, silently choose a new published address after a conflict, or destroy BB data.
- [x] #5 Selected-host setup checks installation, service/boot prerequisites, local application health and private HTTPS reachability with bounded failures and reports the actual endpoint. Any failed required BB operation marks setup incomplete while unrelated work and final logging continue; missing Tailscale authentication/HTTPS permissions is reported, not silently bypassed.
- [x] #6 Temporary mocked/extracted-helper fixtures cover host selection, first install, repeated setup, updates, restart/boot wiring, stable endpoint ownership/conflicts, native dependency policy, failures and unrelated-state preservation. No live setup, BB services, Serve mutations, remote hosts or inference are used in development/tests. Document the separate real boot and remote-browser verification needed at rollout.
- [x] #7 Update README and relevant agent guidance plus ubuntu.sh version/last-change text; preserve the glossary distinction between independent bb main servers and execution machines.
- [x] #8 Ubuntu setup enables BB server management only through BB_SERVER=1 from the process environment or account ~/.env.local, never a hostname allowlist. A nonempty process value takes precedence; unset/0 skips management without removing or stopping existing BB; invalid nonempty values fail before BB changes. Preserve existing environment files. Cover opt-in, default skip, explicit process 0/1 overrides, invalid values and supported native Linux gates in fixtures. Other platform scripts do not install a BB server or desktop client.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Implement Ubuntu BB_SERVER opt-in with process-over-env precedence, strict 0/1 validation, preserved existing env files, independent Paseo/Pi gates and aggregated setup errors.
2. Install stable bb-app with the shared runtime and strict native npm policy. Distinguish ownership from health so an owned damaged install can be repaired; preserve verified old prefixes across compatible Node transitions and validate actual bundled/native artifacts.
3. Use a dedicated systemd app service with lingering, a bundled full launcher, native local identity initialization and readiness checks. Preserve provider credentials and existing BB identities/data. Preflight foreign listeners and conflicting persisted runtime settings.
4. Use a separate lifecycle-coupled foreground Serve user service at the saved fixed DNS/HTTPS port. Validate connected Tailscale CLI/daemon version, DNS and native app/host readiness from generated startup commands. Native daemon foreground conflict protection preserves existing routes. Stop ingress before planned app downtime; restart only after readiness. Keep Portless/ACLs/public access untouched. This is ordinary supervised TCP service ownership, not perpetual atomic protection against arbitrary local port replacement after crashes.
5. Stop/prove owned services stopped before package/config updates, merge configuration through native BB file locks, preserve concurrent writers and restore a previously running deployment when safely possible after failed operations. Keep the failed setup result even if restoration succeeds.
6. Test extracted helpers and actual generated command environments with temporary homes/inert lifecycle commands: fresh install, updates, damaged-package repair, native identity, npm policy, prefix changes, saved endpoint/conflicts, bounded readiness, lock contention/restoration and unrelated-state preservation. Run lint and affected contracts; update docs/version and clearly separate fixture evidence from live rollout checks.

Implementation and parent verification complete. No production install/service/Serve or fleet changes performed.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- User approved two independent stable servers, browser-only elsewhere, existing per-machine credentials, whole-tailnet access/no additional authentication, setup interruptions, unattended startup and failure reporting. Persistent production Tailscale Serve was approved after rejecting Portless URL churn.
- Read-only research identifies devinabox as this Ubuntu x86-64 host. Tailnet/repository history identifies the Beelink as scott-beelink-ubuntu; its current OS details/account still require runtime validation.
- Official bb-app start runs main server plus local execution daemon; ordinary installation does not install a boot service. Persistent Serve survives reboot but not the application itself. Portless development routes/shared proxy stay untouched.
- Tools available: backlog, shellcheck, Python and shared Node. Reviewed Ubuntu main flow, existing Tailscale installer and extracted-helper contract style. Current changes are only CONTEXT.md glossary and this task metadata; no live services changed.

- User challenged the proposed hard-coded host allowlist and requested a variable-based decision. Replaced hostname selection with proposed BB_SERVER=1 opt-in; initial target hostnames are deployment intentions only. Proposed unset/0 skip semantics, process precedence and invalid-value handling are awaiting confirmation. No implementation or live changes made.

- User now explicitly requested: "implement in a subagent on the current workspace". This authorizes implementation of the revised variable-based plan; prior waiting-for-approval wording is historical and no further plan approval is required. Handing off to the configured Implementor profile in this same workspace. Preserve BB_SERVER opt-in semantics and do not deploy to live machines.

- Implementation authorization received. Beginning with fail-closed flag handling and setup error aggregation; production service/ingress must not be approximated without ownership guarantees.

- Added Ubuntu-only BB_SERVER selection with nonempty process override, strict 0/1 validation, and explicit fail-closed status for enabled but unimplemented management. Updated generated env template and version 266. bash -n ubuntu.sh, shellcheck ubuntu.sh, git diff --check pass. No BB package/service/Serve commands were run. Remaining installation, ownership-safe persistent ingress, fixtures, documentation, and rollout checks are not implemented; leaving task In Progress.

- Investigated Tailscale v1.102.4 serve_v2.go: CLI loads config inside runServeCombined, mutates setServe, and writes via SetServeConfig with ETag. The ETag guards concurrent writes after the CLI read, but an external change between setup preflight and the CLI read can become the object of setServe. Checking whether ownership can be proved without route takeover before enabling mutation. Added isolated native Ubuntu gate and command-scoped npm installer; service/route orchestration is still pending.

- Verified Tailscale v1.102.4 cmd/tailscale/cli/serve_v2.go runServeCombined: GetServeConfig occurs after setup preflight; setServe mutates the returned config and SetServeConfig applies ETag only against changes after that read. A foreign route created between preflight and CLI read could be replaced. Native per-node serve CLI has no conditional create/compare-and-swap by expected empty port. Named-service set-config overwrites handlers, and LocalAPI whole-config replacement is excluded by task policy. Consequently the approved per-node route cannot meet the unconditional no-takeover criterion in the presence of concurrent foreign clients through the permitted CLI. setup_bb_server fails BEFORE package/service/route mutation pending a policy decision or supported conditional-claim mechanism.
- Implemented native Ubuntu selection, policy-preserving npm helper (not invoked while ingress blocked), fail-closed error aggregation and an inert extracted-helper flag/npm-denial test. Passed bash -n and shellcheck for ubuntu.sh/test, BB fixture, setup reliability, shared runtime, headless Paseo, Go wiring, Telegram and diff --check. No live service, npm installation or Serve mutation. Task remains In Progress; service/ingress/health AC not met.

- Implementor reported a native Serve preflight/internal-read concurrency gap and stopped with the feature incomplete. Parent is validating that claim and checking whether the plan accidentally demanded a stronger concurrency guarantee than the user requested. Read-only committee launched in the same workspace: Astra 70e5b56f-16e3-4f3b-b68f-bca3f054fb2d and Opus 434a36eb-4b7f-4bfc-bb12-d6fb1b926bd1. No risk waiver, ingress mechanism change or live mutation has been authorized as a result of this review.

- Read-only committee converged: background Serve has the reported preflight/internal-read race, but native foreground Serve has daemon-locked occupied-port validation. Astra and Luna independently verified v1.102.4; Astra also verified v1.92.0 and found v1.90.0 lacks the guard. Foreground + a dedicated Restart=always user unit provides the requested fixed-address reboot persistence without route takeover. No further user risk waiver is needed: address/access/boot semantics remain as approved.
- Plan revised to supervise foreground Serve, preserve its saved port, fail on later foreign occupation, and keep setup health bounded while the unit retries after daemon/session interruptions. No --bg, off/reset, whole-config write, LocalAPI workaround, ACL/operator changes or shared Portless disruption. Original committee IDs: 70e5b56f-16e3-4f3b-b68f-bca3f054fb2d (Astra), b24288b3-c446-4f21-b67f-cee178418e23 (Luna). Other review attempts failed auth/usage limits; no credentials/billing changed.

- Implemented native foreground Serve in dedicated restarting user unit after committee resolution. Conservative CLI+connected daemon floor 1.102.4; no --bg/off/reset/LocalAPI. Saved DNS/origin/port, checked whole-port occupation (including foreground/Funnel), preserved unchanged ingress on app updates, verified foreground route target/readback and bounded local/HTTPS health. Added systemd app unit with bundled full launcher, private managed state, linger check, trusted unit/fragment/drop-in preflight, and stable loopback backend. Added scoped npm lifecycle policy and native-addon loading checks; isolated setup failure aggregation.
- Discovered bb-app config.json stores BB_APP_URL under config.BB_APP_URL rather than the JSON root. Fixed targeted merge and duplicate-key preflight; preserved env.json, project data and unrelated config. Added inert fixtures for selection/process override/platform, npm denial/install/prerelease, port conflict, first install/update/restart failures, stable endpoint, unit ownership, route readback, DNS change and simulated locked foreground races. Passed bash syntax, shellcheck, BB fixtures, setup reliability, shared runtime, headless Paseo, Go wiring, Telegram and diff --check. No live install, service, Serve, model or tailnet browser call occurred.

- Final self-review: only ubuntu.sh adds BB operations; disabled/invalid flags never reach them. Dedicated foreground Serve unit retains the endpoint without altering Portless, Funnel or unrelated routes; unit fragment/drop-in ownership is preflighted. bb-app config merge uses the actual nested config.BB_APP_URL schema, removes only a conflicting BB_APP_URL entry from bb env.json, preserves other environment keys/credentials and rejects malformed/linked metadata. All network/service/npm operations in fixtures are inert; real cold boot, tailnet browser/WebSocket and local agent execution remain rollout checks. Re-ran BB fixture, bash -n, shellcheck, setup reliability, shared runtime, headless Paseo, Go wiring, Telegram and diff --check successfully.

- Parent independently passed bash syntax, shellcheck, BB extracted-helper fixture and git diff --check. Final diff review found unresolved concerns: fixed local backend/daemon ports are not preflighted, package and ~/.bb config/env mutations precede any stop of the running app, and package ownership is bound to an exact mise installation prefix. Reopened for a focused read-only source-backed review by Astra before accepting completion; existing tests do not establish these preservation/update cases. No live changes or extra security scope.

- Final source-backed Astra review substantiates six blockers, not a design change: (P1) foreground ingress starts before verified BB server/host readiness and can publish a foreign HTTP-200 listener on fixed backend ports; (P1) npm update and unlocked config/env rewrites happen before any stopped interval, risking concurrent legitimate data loss; (P2) exact mise-prefix ownership marker blocks compatible Node prefix transitions; (P2) unconditional bare-name npm --allow-scripts overrides narrower existing policy; (P2) persisted BB_DATA_DIR/BB_SERVER_PORT/BB_HOST_DAEMON_PORT can defeat startup arguments; (P2) ingress boot/reconnect bypasses saved DNS/version checks. Also verify actual nonempty web/server/host bundles, not empty launcher wrappers, and test generated commands instead of one active flag/all-success curl mocks. Foreground-native concurrency design remains valid.
- Fix sources: BB launcher at commit 4354b88ce14457fbdf1fc1a8e0db2dd4b5ef90f3 src/launcher.ts (effective settings 946-1013, bundle verification 2054-2127, launch/host identity 2275-2349); packages/config/src/managed-json-file.ts native locking; npm/cli v11.19.0 lib/utils/resolve-allow-scripts.js 81-102 precedence. Requested targeted fixes and generated-command fixtures; no live verification or additional auth/security layers.

- Review remediation underway (not complete): reject conflicting persisted listener/data overrides before npm; refuse pre-existing npm allow-scripts policies rather than replace exact-version denies, and probe scoped flag behavior; added native npm resolver fixture confirming CLI precedence. Added pending ownership record for compatible mise prefix transitions (old marker retained until service health) and full nonempty regular bundled app/server/host artifact plus CLI-bin identity validation. Updated inert fixture metadata, override denial, native policy and bundle files. P1 ingress/startup identity, stopped update transaction/native JSON lock, boot preflight and independent generated-command tests remain open; do not treat current passing mocks as rollout safety.

- Source-backed backend ownership issue remains after independent P2 repairs: bb accepts only TCP bind hosts 127.0.0.1/0.0.0.0 (packages/config/src/env-vars.ts parseServerBindHost lines 108-115); native launcher validates its own child by launchId and daemon host/status (launcher.ts 2249-2349) but current generated Tailscale unit proxies a reusable TCP port without binding it to that child. BindsTo/ExecStartPre/periodic readiness can reject a foreign HTTP-200 server at startup and shorten outage exposure, but after an owned listener dies a foreign process can bind before the next poll or systemd stop propagation. Per-request binding through a managed local proxy or isolated network namespace would close this gap but is beyond current approved direct-Serve target/minimal scope. Need parent decision whether bounded lifecycle/watchdog semantics satisfy the no-foreign-successor criterion or whether an internal proxy may be authorized. The feature is not ready for rollout; do not mark Done.
- Partial code improvements in this iteration: preflight persisted listener/data override conflicts before package mutation; reject existing npm allow-scripts policy and probe native flags; native resolver fixture demonstrates CLI policy replacement; pending package-owner enables compatible mise-prefix transition while retaining old prefix; verify nonempty real bundled paths and executable identity with inert fixtures. These pass current BB fixtures/syntax/shellcheck/diff, but P1, native JSON locking/stop transaction, generated unit execution and boot validation remain outstanding.

- Re-ran BB fixture, bash syntax, shellcheck, setup reliability, shared-runtime, headless, Go wiring, Telegram and diff --check: all pass for partial changes. Added explicit do-not-opt-in/deploy warning to README/CLAUDE and incremented Ubuntu version to 267. Current fixtures still do not exercise generated units or native stop/lock/readiness. Parent verification DoD #3 remains unchecked; task stays In Progress.

- Added fixture coverage for all four persisted listener/data overrides in config and env without host /etc/os-release dependence; stable prefix transition helper preserves old package and records pending new package until health. Current tests still pass but do not exercise generated ingress/bootstrap nor native JSON locks. The direct TCP successor-listener exposure is a new design-level conflict distinct from foreground Serve route ownership: native bb supports only TCP bind hosts, and watchdog/systemd BindsTo cannot atomically prove ownership for each forwarded connection. Requiring an internal validating proxy or network namespace exceeds the requested direct-Serve/minimal ingress plan. Awaiting parent decision on allowing such a gate versus explicitly accepting a bounded lifecycle race; feature remains unsafe to opt in.

- Parent scope correction after the latest partial implementation: preventing an arbitrary same-host process from atomically acquiring a TCP port after an unexpected BB exit was an overstrong condition introduced during review, not a user requirement. Do not add a validating proxy, network namespace or new authentication layer. The authorized production model is ordinary supervised direct Serve: reject foreign listeners before setup/start, verify native BB server and local execution readiness before exposure, couple managed ingress/app lifecycle, stop ingress before planned BB downtime, retry saved ports and fail on detected conflict. Do not promise perpetual atomic TCP-backend ownership. Preserve the already-proved native foreground Tailscale no-route-takeover guarantee.
- Remaining genuine work includes verified stopped update ordering, native configuration locking and preserving merges, generated boot/restart prerequisites/identity/readiness tests, honest evidence and docs. These were not completed by the prior implementor. Handing repair to a discovered higher-reasoning Pi/OpenAI Luna agent because configured Planner is not an implementor and the low-reasoning Implementor repeatedly stalled. No additional production deployment/authentication/security scope is authorized. Parent review still required before Done.

- Final review added generated-wrapper MainPID/cmdline verification, strict saved-endpoint metadata validation, restoration of the prior active service after failed update/readiness/HTTPS checks, and package-prefix/artifact ownership fixtures. Added foreign unit/drop-in, disconnected-tailnet, owned-listener, bounded health, boot wiring, and stopped-update coverage.
- Final checks passed: Bash syntax and ShellCheck for ubuntu.sh and tests/bb-server-contract.sh; BB server contract; setup reliability; shared Node runtime; headless Paseo daemon; Go wiring and Muse profile; release-channel; Telegram alerts; git diff --check. Optional PowerShell fixtures were skipped because PWSH_BIN is unavailable; no PowerShell scripts changed.
- No live installation, npm package mutation, systemd service change, Tailscale Serve mutation, or deployment was performed. Leaving TASK-45 In Progress for parent verification; DoD #3 remains unchecked.

- Final preflight tightening now rejects unowned, linked, hard-linked, or group/world-writable bb config/env metadata before stopping services or changing packages. Contract coverage verifies this fails before install.
- Re-ran the complete listed validation matrix after the final script change; Bash syntax, ShellCheck, BB contract, setup reliability, shared Node runtime, headless Paseo, Go wiring/Muse profile, release-channel, Telegram and diff check all passed. Optional PowerShell fixtures remain skipped because PWSH_BIN is unavailable.

- Parent independently passed updated Bash syntax/ShellCheck, BB generated-command fixtures, setup reliability, shared-runtime, headless Paseo, Go wiring and Telegram contracts (optional PowerShell/runtime integration fixtures skipped when unavailable). Final Astra review confirms four ordinary startup/recovery blockers: ingress unit omits BB_PACKAGE_BINARY although its guard requires it; fresh BB requires preexisting native host identity even though full launcher initializes it locally; owned unhealthy package cannot be repaired because preflight requires full health; native config lock/merge failure bypasses restoration after stopping services. Requesting targeted fixes with actual generated-unit environment fixtures, no-preseed first launch, healthy->failed->repaired committed owner, and lock-timeout restoration. No new security/proxy requirements.

- Final review fixes: pass `BB_PACKAGE_BINARY` in the rendered ingress unit; the contract parser executes generated app/ingress commands using only their rendered Environment values (no inherited mock environment).
- Fresh-install preflight now accepts absent local identity; the unmocked post-launch readiness check requires the inert launcher-generated, private host ID. Regression also rejects malformed, conflicting, and linked existing identity metadata.
- Separate owned-target safety from artifact health so a committed owner can repair a missing BB bundle without moving ownership; a package-root symlink replacement still fails. Prior-package rollback continues to require full artifact verification.
- Native config-lock timeout now reports failure and restores an active prior app/ingress without rolling back config files. The end-to-end fixture simulates a concurrent writer under the held lock; its latest config/env changes survive restoration.
- Verification passed: BB contract, Bash syntax, ShellCheck, `git diff --check`, setup reliability, shared Node runtime, headless Paseo, Go/Muse wiring/profile, release-channel, and Telegram contracts. PowerShell wrappers were skipped (`PWSH_BIN` unavailable). No live install, systemd, Tailscale Serve, deployment, or model operation.

- Parent final verification confirmed all four targeted corrections: rendered ingress now receives BB_PACKAGE_BINARY; native first launch may initialize missing local BB identity; unhealthy but positively owned package targets remain repairable; config lock/merge failures attempt bounded prior-service restoration while keeping failure status and concurrent config writes. Reviewed generated-unit environment/fresh-HOME/committed-owner repair/lock-failure fixtures and source paths. No perpetual TCP-ownership guarantee added.
- Parent reran final Bash syntax, ShellCheck, BB contract, setup reliability, shared Node runtime, headless Paseo, Go wiring, Muse profile, release-channel, Telegram and git diff --check: available tests passed. Optional PowerShell/native integration cases reported skips when prerequisites were unavailable. Removed generated Python bytecode cache only. Updated README/CLAUDE to remove stale development-blocker warnings, document exact runtime/Tailscale prerequisites, and explain app-readiness-triggered ingress boot.
- AC #2/#3 are verified as implementation/fixture contracts, not claimed live reboot evidence. Real cold boot, logout, remote tailnet UI/WebSocket and local execution remain documented rollout verification. No real credentials, live services/routes, remote hosts or model requests changed; no commit/push performed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented opt-in stable bb main-server setup on native Ubuntu using BB_SERVER=1, with process-over-env precedence and no hostname allowlist. Other machines remain unchanged; existing credentials, BB data, npm policy and unrelated services/routes are preserved.

Changes:

- Managed full-launcher and lifecycle-coupled foreground Tailscale Serve user services, native readiness checks, saved private HTTPS endpoint, lingering and automatic recovery.
- Stopped updates with native config locking, concurrent-writer preservation, owned damaged-package repair, compatible shared-Node prefix transitions and safe service-restoration attempts on failure.
- Realistic inert fixtures exercise generated unit environments, fresh local identity creation, port/version/DNS gates, updates and lock recovery. Updated Ubuntu version, README, agent guidance and glossary.

Verification:

- Parent passed Bash syntax/ShellCheck, BB fixtures, setup reliability, shared runtime, headless Paseo, Go wiring/Muse, release-channel, Telegram and diff checks. Optional PowerShell/native integration fixtures skip without their prerequisites.
- Source-backed foreground race behavior remains explicitly modeled rather than claimed as a live daemon test.
- No deployment or live service/network changes. Cold boot, logout, remote tailnet UI/WebSocket and local execution checks remain rollout steps.
<!-- SECTION:FINAL_SUMMARY:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Run shellcheck and Bash syntax checks on modified shell scripts, the BB contract tests, setup reliability and affected shared-runtime/headless/Go wiring regressions.
- [x] #2 Review the diff for scope, secret safety, preservation of unrelated services/routes/data, and accurate fixture-versus-live verification claims.
- [x] #3 Resolve the final source-backed implementation review findings and obtain parent verification before marking Done; generated-command tests must exercise startup gates, owned listener readiness and stopped update ordering.
<!-- DOD:END -->
