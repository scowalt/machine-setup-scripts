---
date: 2026-06-24
topic: headless-paseo-daemon
---

# Headless Paseo Daemon Setup

## Summary

`HEADLESS=1` setup runs will install Paseo and configure its daemon as an always-on, boot-managed service. The setup must keep Paseo's relay-based remote connection model, leave pairing manual, and fail clearly when the daemon service cannot be installed, enabled, and verified.

---

## Problem Frame

Headless development machines need to be reachable by the Paseo coding app without depending on an interactive login session. A one-time daemon start during setup is not enough because the process may disappear after logout, reboot, or session teardown.

This repository already uses `HEADLESS=1` as a signal for remote-operability behavior such as VPS-style SSH handling, passwordless sudo on Linux, and no-sleep/screen-sharing configuration on macOS. Paseo should follow that same contract so headless machines are consistently prepared for remote coding access.

---

## Actors

- A1. Machine owner: Runs setup scripts and later pairs machines with the Paseo app or CLI.
- A2. Headless machine: Runs the setup script with `HEADLESS=1` and must remain reachable after reboot without interactive login.
- A3. Paseo client: Uses Paseo's existing pairing and relay model to connect after setup is complete.
- A4. Setup script: Installs tools, configures services, verifies readiness, and exits with success or failure.

---

## Key Flows

- F1. Headless setup provisioning
  - **Trigger:** A setup script runs with `HEADLESS=1`.
  - **Actors:** A1, A2, A4
  - **Steps:** The script installs Paseo, configures a boot-managed daemon service, enables/starts it, and verifies the daemon is reachable locally.
  - **Outcome:** The machine has a persistent Paseo daemon ready for later pairing.
  - **Covered by:** R1, R2, R3, R4, R5

- F2. Non-headless setup run
  - **Trigger:** A setup script runs without `HEADLESS=1`.
  - **Actors:** A1, A4
  - **Steps:** The script continues normal provisioning without installing or configuring Paseo solely for this feature.
  - **Outcome:** Non-headless machines are not given new Paseo background services by this work.
  - **Covered by:** R6

- F3. Later manual pairing
  - **Trigger:** The machine owner wants to connect the Paseo app or CLI to a provisioned headless machine.
  - **Actors:** A1, A2, A3
  - **Steps:** The owner requests a pairing offer from the running daemon and completes pairing through Paseo's normal flow.
  - **Outcome:** The client connects through Paseo's default relay path without this setup feature printing or storing pairing material.
  - **Covered by:** R7, R8

---

## Requirements

**Headless installation and service behavior**
- R1. When a setup script runs with `HEADLESS=1`, it must install or update the Paseo CLI/daemon package needed to run a local Paseo daemon.
- R2. When `HEADLESS=1`, the setup must configure Paseo as a boot-managed background service using the platform's appropriate service mechanism where supported.
- R3. The configured daemon must be able to start without an interactive login session on platforms that support boot-managed user services.
- R4. The setup must enable and start the Paseo daemon service during the run.
- R5. The setup must verify the daemon is running and locally reachable before considering Paseo setup complete.

**Failure and skip behavior**
- R6. When `HEADLESS` is not `1`, this feature must not install Paseo or create/start a Paseo daemon service.
- R7. When `HEADLESS=1` and Paseo installation, service configuration, service enablement, service start, or health verification fails, the setup script must fail rather than warn and continue.
- R8. If a platform or future setup script adopts `HEADLESS=1` but cannot support a real boot-managed Paseo daemon, it must fail clearly instead of silently skipping Paseo daemon setup.

**Connection model and pairing**
- R9. The setup must preserve Paseo's default relay-based remote connection model and must not require opening inbound network ports for this feature.
- R10. The setup must not perform automatic pairing, print pairing links as part of normal success output, or require pairing for service health verification.
- R11. The setup should leave the owner able to run Paseo's normal pairing command later after the daemon is running.

---

## Acceptance Examples

- AE1. **Covers R1, R2, R4, R5.** Given a supported headless machine, when setup runs with `HEADLESS=1`, Paseo is installed, the daemon service is enabled and started, and setup exits successfully only after a local daemon status check passes.
- AE2. **Covers R6.** Given a non-headless machine, when setup runs without `HEADLESS=1`, the script does not install Paseo or add a Paseo background service for this feature.
- AE3. **Covers R7, R8.** Given a headless machine where the service cannot be enabled or verified, when setup reaches Paseo daemon setup, the script exits with failure and a clear error rather than continuing as if the machine is remote-operable.
- AE4. **Covers R9, R10, R11.** Given a successful headless setup, when the owner later wants to connect the Paseo app, they can request a normal pairing offer from the running daemon; setup itself did not expose inbound ports or print/store a pairing URL.

---

## Success Criteria

- A headless machine that completes setup can be rebooted and still have a Paseo daemon available for later client pairing without an interactive login.
- The setup result is unambiguous: if `HEADLESS=1` succeeds, the Paseo daemon service is installed, enabled, started, and verified; if not, setup fails.
- Non-headless machines are unaffected by this feature.
- A downstream implementation plan can map each supported setup script to a platform service strategy without inventing product behavior, pairing behavior, or failure policy.

---

## Scope Boundaries

- No automatic Paseo pairing or pairing-link display during normal setup success.
- No installation of Paseo on non-headless machines as part of this feature.
- No replacement of Paseo's existing relay-based remote connection model.
- No opening public or LAN inbound ports solely for Paseo connectivity.
- No provider credential setup beyond relying on the repository's existing coding-agent/provider installation patterns.

---

## Key Decisions

- Headless-only installation: Paseo setup is tied to `HEADLESS=1` because the current need is remote operability for headless machines, not adding another CLI everywhere.
- Boot-managed service over one-shot daemon start: The daemon must survive reboot/logout, so setup cannot rely on `paseo daemon start` alone.
- Fail-fast on headless: `HEADLESS=1` is treated as a hard remote-operability contract, so a missing or unhealthy Paseo daemon is a setup failure.
- Manual pairing: Pairing is easy for the owner to do later, and keeping it out of setup avoids noisy or sensitive pairing output.

---

## Dependencies / Assumptions

- Paseo's CLI package remains installable as a global Node/Bun package and includes the local daemon commands.
- Paseo's default relay remains enabled by default and sufficient for remote app/CLI connection without inbound ports.
- Headless setup scripts already have or can obtain the privilege needed to configure boot-managed services.
- Provider CLIs and credentials remain a separate concern handled by existing setup paths or manual authentication.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R2, R3][Technical] Which service mechanism should each current setup script use to guarantee no-login startup on its platform?
- [Affects R5][Technical] What exact health check should count as daemon verification while avoiding a dependency on pairing?
- [Affects R7][Technical] How should failure be surfaced consistently across Bash and PowerShell setup scripts?
