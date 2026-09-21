# Design: truthful Homebrew results and bounded Paseo process inspection

## Status and scope

The user approved the outcome and safety policies during the September 19 log-audit follow-up. This document makes those policies implementation-ready; it does not authorize a live setup run or fleet repair.

Design and implementation baseline: upstream `main` at `9e24b31f28626074e177fb38a471904ced247a85`. The older audit checkout (`f92471e`) was fast-forwarded before implementation, preserving the intervening changes and approved glossary. Implementation is tracked in Backlog TASK-40 and TASK-41 on `fix/setup-results-and-process-inventory`.

Deliver as two independently testable fixes:

1. Propagate incomplete Homebrew updates into the macOS setup result.
2. Bound the shared Muse helper's Linux process inspection without weakening owner verification, and distinguish expected deferrals from unverified safety checks.

No automatic CLT upgrades, cask reinstalls, trust changes, privilege escalation, procfs permission changes, remote host changes, or unrelated cleanup. Do not fix the separate Infisical repository or ScoBot skill-link issues in these changes.

## Evidence and confidence

- `scott-macbook-m3/2026-09-18-20-12-11-356.log`: Homebrew reports `upgrade=1` after unsupported CLT errors, but setup prints `Setup complete!`. An extracted-function fixture against the reference commit confirms final status 0. This is a confirmed reporting defect, not a new defect introduced by the Node fix.
- Ten Linux runs report `Paseo Muse deferred: process-inventory-unverified`. Representative logs are `arcane/2026-09-18-02-14-17-536.log`, `bazzite/2026-09-14-02-59-12-915.log`, `devinabox/2026-09-17-23-17-23-138.log`, and `scott-beelink-ubuntu/2026-09-18-00-06-39-203.log`.
- An extracted inventory fixture confirms that an unreadable command line from an unrelated foreign-user process aborts inspection. The logs do not identify the failing syscall or process, so this is a demonstrated defect and plausible explanation, not proof of the cause of every logged deferral. Improved diagnostics are part of the fix.

## Agreed outcome model

| Outcome | Final status | Required behavior |
| --- | --- | --- |
| Required work and verification succeed | Zero | Report success truthfully. |
| Intentional exclusion or platform ineligibility | Zero unless other work failed | Preserve the existing skip policy. |
| Expected Paseo deferral | Zero unless other work failed | Explain Desktop/self-hosted ownership and the manual rerun step; do not claim the profile was updated. |
| Failed required operation or unverified required result | Nonzero | Continue unaffected work, report an incomplete setup run, and finalize/upload its log. |
| Unverified Paseo safety check | Nonzero | Block dependent profile/daemon mutations and surplus-CLI cleanup; continue unrelated setup work. |

An expected Paseo deferral requires an established Desktop-owned or self-hosted condition. Unknown ownership is not an expected deferral. A verified custom-home transaction may succeed while deliberately blocking the later default-home daemon installer; preserve that distinction.

## Fix 1: Homebrew result propagation

### Behavior

- `update_brew()` returns nonzero if update, upgrade, or required unpin cleanup fails.
- Successful command exits are insufficient: failure to verify the remaining package state, unresolved unpinned outdated packages, or established trust-related skipped work also makes the phase incomplete.
- Preserve intentional user pins and the existing temporary tmux exclusion. An ordinary warning alone is not a failure; use phase results and required postconditions, not broad output matching.
- Preserve all phase statuses through cleanup. Always attempt the existing unpin cleanup, and retain its trap fallback when cleanup is unsuccessful or interrupted.
- The final macOS caller aggregates the helper's failure into `_setup_had_errors`. It still runs the pending-reboot check and log finalization, without replacing earlier failures with a later success.
- Continue to print the existing actionable Homebrew diagnostics. Do not retry with weaker security or perform host remediation automatically.

### Homebrew verification

Use extracted functions and a mocked finalization path, not a full sourced or executed setup script. Assert the final setup status and completion banner, not merely the absence of `Homebrew updated.`.

| Fixture | Expected result |
| --- | --- |
| Update, upgrade, unpin and postchecks succeed | Zero and truthful success. |
| Update, upgrade, or unpin fails independently | Nonzero; unpin attempted where applicable; incomplete banner. |
| Commands succeed but outdated or pin inventory cannot be read | Nonzero; verification diagnostic. |
| Unpinned outdated package remains | Nonzero; identify the outstanding package. |
| Only user-pinned packages or temporarily excluded tmux remain | Zero, absent other failures. |
| Trust checks establish skipped work | Nonzero; no automatic trust change. |
| Earlier setup failure followed by successful Homebrew phase | Earlier failure remains nonzero. |
| Homebrew fails but subsequent reboot/log operations succeed | Failure retained; unrelated work and log finalization still run. |
| Existing interruption/cleanup fixture | Existing tmux cleanup and signal behavior preserved. |

Extend `tests/setup-reliability-contract.sh` and the appropriate final-result/log contracts. Existing Homebrew assertions predominantly inspect warning text; add caller-level failure propagation coverage. Do not rewrite unrelated platform package-manager behavior.

## Fix 2: account-scoped Linux process inspection

### Identity and classification

The relevant boundary is the setup account and the verified managed daemon, not every process on the host. This is not a guarantee against arbitrary privileged filesystem editors.

1. Collect basic process identity and ancestry before sensitive details: PID, parent PID, process start identity, state, and the real/effective/saved/filesystem UID tuple.
2. Derive account membership from validated kernel process metadata, not `stat('/proc/<pid>').uid`. Linux changes procfs ownership when a process is not dumpable; a root-owned entry can still describe an account-owned process.
3. Classify a process as foreign only when all UID fields are verified to be outside the setup account and it is not a required verified owner/service participant. Any account-matching UID keeps it potentially relevant. Missing, malformed, ambiguous, or changing identity is not proof of foreign ownership.
4. Retain required ancestry information for foreign processes, but do not read their command lines or environments merely to exclude them later. Existing owner/cgroup/descendant checks must still reject unexpected participants in a managed service.
5. For potentially relevant live processes, retain the current command, environment-marker, cgroup and ancestry evidence needed to detect renamed daemons and unexpected writers. A benign process name is not enough to skip environment verification.
6. Do not reinterpret unreadable required metadata as an empty command, empty environment, or absence of a writer. Report an unverified safety check.

### Process races and repeated verification

- Bind a process record to a stable process instance. Use a pinned proc-directory handle where supported, or explicit before/after start-identity and UID checks; do not combine records across PID reuse or identity changes.
- A process that disappears during collection may be omitted only after verifying that the same instance has gone. Permission denial is not disappearance. A missing required ancestor or owner invalidates the relevant check.
- Positively verified dead/zombie processes do not execute new writes, but their ancestry and any surviving service descendants still matter. An empty command line alone does not establish that a process is dead.
- Keep checks bounded. If churn prevents a defensible snapshot, stop with a controlled incomplete result instead of retrying indefinitely or weakening checks.
- Preserve repeated inspections before mutation, after stopping an identified owner, during native PID reservation, and before committing the profile. A snapshot does not replace the existing native startup lock or service-ownership checks.

### Results, diagnostics and wrappers

- Keep successful verification, expected deferral, deliberate ineligibility and blocked verification as distinct outcomes. Do not map every controlled refusal to warning-only success.
- An unverified inventory/ancestry/owner/service check returns nonzero and sets the existing dependent-daemon block flag. Preserve the block even if later unrelated work succeeds.
- Desktop/self-hosted deferrals remain warning-only when established safely. Existing native platform, macOS canary, custom-home and Windows/WSL headless restrictions remain unchanged.
- Do not mutate anything after a failed initial preflight. If failure occurs after an authorized service stop, preserve the existing safe restoration procedure; restoration failure is separately reported and remains nonzero. Never start a replacement owner or override a newly appeared writer to force recovery.
- Emit only allowlisted operation labels and reason/native error codes, for example `inventory-status: EACCES` or `inventory-identity: changed`. Never emit process arguments, environment contents, custom paths, arbitrary exception text or raw child stderr.
- Carry the controlled diagnostic and failure status through Bash and PowerShell wrappers. Unknown or malformed helper output fails closed rather than being accepted as successful verification.
- Keep embedded helper copies identical in `mac.sh`, `ubuntu.sh`, `wsl.sh`, `pi.sh`, `bazzite.sh`, and `win.ps1`. Only Linux process collection changes; platform-independent result classification and wrappers require cross-platform coverage.

### Muse verification

Extend the actual shared helper's fixtures, rather than testing only a detached classification utility. Use temporary homes, mock procfs/process metadata and mock lifecycle commands. Never inspect or change live daemon state in these tests.

| Fixture | Expected result |
| --- | --- |
| Verified unrelated foreign UID; cmdline/environment would deny access | Verification proceeds; those sensitive reads are never attempted. |
| Root-owned procfs entry whose UID tuple belongs to the account | Remains potentially relevant; never skipped as foreign. |
| Mixed UID tuple containing the account UID | Remains potentially relevant. |
| Missing, duplicate, malformed or unreadable identity fields | Controlled nonzero safety block; no mutations. |
| Relevant process cmdline/environment/cgroup denied | Controlled nonzero safety block; no empty-value fallback. |
| Renamed daemon detectable only through environment or ownership evidence | Still detected and preserved. |
| Foreign setup ancestor | Basic ancestry retained; no unnecessary sensitive reads. |
| Owner/service descendant contradicts the foreign classification | Not excluded; dependent mutations blocked unless ownership is proved. |
| Process exits, PID is reused, or UID/start identity changes mid-read | No mixed-instance record; verified disappearance or controlled failure. |
| Verified zombie plus live service descendants | Zombie not mistaken for a writer; descendants still checked. |
| Unverified owner in profile-update and `verify-owner` modes | Nonzero and dependent daemon/cleanup block retained. |
| Established Desktop-owned or self-hosted execution | Existing expected deferral, no mutation, zero absent other failures. |
| Verified custom home or ineligible headless platform | Existing policy preserved; no default-home fallback. |
| Failure after service stop | Existing safe restoration attempted; failed restoration cannot be hidden. |
| Secrets in mocked process fields, exceptions, stderr or malformed helper output | No secret output; unrecognized results fail closed. |
| Helper fails but unrelated work and log finalization succeed | Final run remains nonzero and its log is finalized. |

Primary suites: `tests/paseo-muse-profile-contract.sh`, `tests/test_paseo_muse_profile.py`, and the Muse PowerShell fixtures with `PWSH_BIN`. Also run affected headless, CLI-cleanup, release-channel, profile-permission and Go wiring contracts, plus shared-runtime contracts if their invocation changes. Include six-copy equality and wrapper propagation assertions. Native Windows limitations must be reported rather than inferred from mocks.

## Implementation and review boundaries

- Implement the two fixes separately from current upstream; keep this design and the glossary additions when moving to the implementation branch.
- Before implementation, create or select the corresponding Backlog tasks using the CLI and record their acceptance criteria. Avoid allocating new task IDs from this stale audit checkout.
- Add failing regression fixtures before changing the relevant functions. The two audit fixtures already establish the narrow defects; implementation tests must also cover the real caller/wrapper seams and safety cases above.
- Increment each modified setup script's version and update its change description. Run ShellCheck on modified Bash scripts, relevant fixture suites, and documentation lint.
- No live setup, daemon restart, model request, remote deployment, host permission repair or package-manager mutation as validation. Mock these operations.
- If the Linux failure remains on a future user-authorized setup run, use the new controlled diagnostic to choose the next investigation; do not claim this fixture proves every audited host has the same cause.

## Verification limits

Validation uses extracted helpers and actual caller/wrapper slices with temporary homes and mocked process/service operations. Native Paseo 0.8 PID-lock contenders also run only in temporary fixtures. PowerShell wrapper and simulated ACL tests run under PowerShell on Linux; this is not native Windows ACL verification. No live macOS Homebrew upgrade, host process inventory, setup run, model request or daemon restart is part of development validation. A later user-authorized run is still needed to confirm the source of any remaining host-specific deferral.

## References

- [Reference macOS implementation](https://github.com/scowalt/machine-setup-scripts/blob/9e24b31f28626074e177fb38a471904ced247a85/mac.sh)
- [Reference shared Muse implementation in ubuntu.sh](https://github.com/scowalt/machine-setup-scripts/blob/9e24b31f28626074e177fb38a471904ced247a85/ubuntu.sh)
- [Linux procfs ownership and dumpability](https://man7.org/linux/man-pages/man5/proc_pid.5.html)
- [Linux process status, state and UID tuple](https://man7.org/linux/man-pages/man5/proc_pid_status.5.html)
