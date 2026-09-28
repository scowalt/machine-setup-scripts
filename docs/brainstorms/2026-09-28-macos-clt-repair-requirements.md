---
date: 2026-09-28
topic: macos-clt-repair
---

# macOS Command Line Tools Repair

## Status

The user approved the policy recommendations in two design rounds. This document records the agreed requirements, not an implemented feature or approval to run updates on a real Mac. Implementation planning remains next.

## Problem

The macOS setup script now correctly reports Homebrew developer-tool compatibility failures, including installed CLT that lacks support for the running macOS. Existing tools are left unchanged, even when Apple offers a suitable update. Homebrew-dependent work can then continue and produce additional failures.

An installed toolchain, an available update, and verified macOS developer-tool readiness are different facts. An empty update listing does not establish readiness. A successful installer alone does not establish readiness either.

The desired outcome is a bounded, non-destructive repair opportunity followed by verification, with dependent work blocked when readiness remains unresolved.

## Approved Decisions

### Automatic repair

- Main-user setup may automatically attempt an in-place update when the selected standalone CLT is confirmed incompatible and Apple offers an explicitly identified CLT update.
- Limit recovery to a bounded attempt, followed by fresh compatibility verification. Do not loop through installations until something passes.
- Healthy tools do not need an update merely because a newer version is offered.
- Do not treat unavailable or failed diagnostic discovery as proof that CLT needs updating. Unverified readiness remains incomplete, without speculative repair.
- Preserve existing tool installations and developer selection. No deletion, forced replacement, automatic switch away from full Xcode, unrelated macOS update, or automatic reboot belongs to this feature.
- Existing first-time installation remains a separate path. Do not reuse its installation-discovery workaround against an existing toolchain.

### No automatic repair available

- If Apple offers no suitable CLT update, leave remediation manual. Do not download an unverified package or weaken the compatibility checks.
- Selected full Xcode and other selections outside the verified standalone CLT case remain manual remediation cases.
- Report the selected toolchain, relevant version information, failed or unavailable checks, and the Apple Developer download link. Distinguish no offered update from a failed update query.
- Secondary-user setup verifies readiness but does not repair the shared developer tools. It explains when the machine owner must perform repair.

### Privilege and interaction

- During an eligible repair, allow one normal sudo authentication opportunity only when an interactive terminal is available and `HEADLESS` is not exactly `1`.
- Headless and terminal-less runs must use already-available privileges or report repair blocked. Never wait on an authentication prompt or open a GUI.
- Do not change sudo policy, introduce persistent elevated access, or broaden unrelated setup operations' privilege behavior.
- If a restart is necessary, report the manual next step. Never reboot automatically or resume dependent work without verified readiness.

### Dependent work and final result

- Unresolved incompatibility or unverified readiness blocks installations and upgrades that depend on healthy developer tools, including affected Homebrew operations.
- Continue only demonstrably independent work. Do not describe a step as independent solely because it has a different installer; account for its prerequisites.
- Preserve log finalization and provide one clear final remediation summary, identifying work skipped because readiness was unresolved.
- An initial incompatibility finding that is repaired successfully does not permanently poison the final result. Resume dependent work after successful repair and verification.
- Actual failed installation, query, or cleanup operations remain setup failures. Never erase unrelated earlier failures when readiness recovers.
- A run with unresolved readiness, failed required operations, or unverified required results is an **incomplete setup run** and finishes nonzero.

## Acceptance Scenarios

| Scenario | Required outcome |
| --- | --- |
| Selected tools pass compatibility checks | No repair; normal dependent work proceeds. |
| Main-user run, incompatible standalone CLT, suitable Apple update, privilege available | Targeted in-place update and fresh verification; dependent work resumes only when readiness is verified. |
| Successful repair after an initial compatibility finding | The finding alone does not make the final result fail; unrelated failures are preserved. |
| Installer fails, even if subsequent checks happen to pass | The installation failure remains reflected in the final result. |
| Installation succeeds but compatibility still fails | No repeated installation attempts; dependent work is skipped and the run remains incomplete. |
| No suitable update is offered | No installation workaround or deletion; manual guidance and incomplete result. |
| Update query fails or compatibility cannot be verified | Report the actual uncertainty/failure; no speculative repair or dependent work. |
| Selected full Xcode or another non-eligible toolchain | Preserve installation and selection; manual remediation if readiness fails. |
| Secondary-user run encounters incompatibility | No shared-toolchain repair; identify the owner action and skip dependent work. |
| Headless or terminal-less run lacks usable privileges | No prompt or GUI; repair is blocked and independent work/log finalization continue. |
| Eligible interactive run needs authentication | One normal authentication opportunity; refusal/failure does not bypass the readiness gate. |
| Update requires a restart before tools become ready | No automatic reboot; report the restart and keep dependent work blocked. |
| Fresh machine without developer tools | Preserve the existing first-time installation behavior and subsequent readiness verification. |

## Scope and Verification Boundaries

- Production changes belong to `mac.sh`, its version/change description, and relevant documentation. Other platform setup behavior is unchanged.
- Audit actual callers and prerequisites when planning the readiness gate; do not merely set a failure flag while continuing dependent mutations.
- Extend extracted-helper and actual-caller fixtures to exercise repair eligibility, targeted update selection, privilege/terminal gates, post-repair verification, skipped dependent work, continued independent work, and final-result preservation.
- Use temporary homes and inert platform, Homebrew, privilege, and lifecycle commands. Never run live setup, developer-tool updates, or remote machine changes during development.
- Run the macOS CLT fixtures, Homebrew result tests, setup reliability contract, affected pending-reboot and weekly regressions, Bash syntax checks, ShellCheck, and diff checks.
- Linux fixtures cannot establish native Apple update behavior. Keep native macOS verification explicitly outstanding until evidence from an authorized Mac run is available.

## References

- [Domain vocabulary](../../CONTEXT.md)
- [macOS setup script](../../mac.sh)
- [CLT helper and caller fixtures](../../tests/test_macos_clt.py)
- [Homebrew result fixtures](../../tests/test_homebrew_results.py)
- [Setup reliability contract](../../tests/setup-reliability-contract.sh)
- [Apple Developer downloads](https://developer.apple.com/download/all/)
