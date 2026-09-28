# BB preparation permissions: approved design

Status: implemented and independently reviewed under TASK-51. Isolated regression and lint checks passed; live rollout remains unverified and is not authorized.

## Problem and evidence

The reported Ubuntu v276 run on `devinabox` used the ScoBot account. Its local log was `2026-09-28-131312.log`; the authenticated collector upload is [2026-09-28-17-14-14-644.log](https://logs.scowalt.com/logs/devinabox/2026-09-28-17-14-14-644.log).

Read-only metadata inspection found group-writable service directories (`0775`) and service files (`0664`). Temporary fixtures using the real extracted BB preparation helper reproduce the exact generic preflight failure independently for a writable ancestor and for a writable unrelated service file. Equivalent fixtures with `0755` directories and `0644` files pass. These results establish permission blockers, not the absence of other blockers on the real account.

TASK-47 already demonstrated that native Chezmoi can restore group-write permissions from an inherited `umask 0002`. Its existing protection applies only to Ubuntu `BB_SERVER=1` runs. Preparation-only accounts do not receive that protection.

## Outcome

Eligible BB preparation runs must not fail because an ordinary setup-managed Chezmoi apply introduces inherited group/world-write permissions. Existing managed paths should converge on rerun through Chezmoi, without giving BB preparation ownership of unrelated configuration.

If explicit permission policy, unmanaged paths or another safety condition still prevents preparation, setup must explain the safely observable blockers, preserve state and finish with an incomplete setup result. Successful preparation still means installed and verified software, not enrollment or daemon readiness.

## Agreed scope

- Cover `ubuntu.sh`, `mac.sh`, `pi.sh`, `bazzite.sh` and `wsl.sh`.
- Preserve native Windows behavior and all existing platform and exact `HEADLESS=1` gates.
- Retain the existing Ubuntu server dotfile protection.
- Add protection for eligible, non-deferred BB machine preparation.
- Do not introduce the additional restriction solely for preparation that is deferred because of existing BB state, enrollment, known services or data/prefix overrides.
- Keep standalone Chezmoi commands, automatic dotfile updates and persistent dotfile policy outside this patch.

Eligibility must agree with existing effective flag precedence, platform gates and role-deferral rules. Do not create a second role policy, require a working Node/npm installation to protect an earlier dotfile apply, or perform package/lifecycle operations to decide eligibility. Actual preparation still performs its own checks before mutation.

A deferred preparation run continues ordinary dotfile handling with its existing behavior; this patch does not promise to stop all changes made by that ordinary apply. It adds no BB-driven permission restriction to that deferred path. An opted-in Ubuntu server continues to receive its already-established protection.

## Permission authority

Chezmoi owns managed dotfiles. BB preparation owns its separate preparation package tree. Reading a service registration during preflight does not transfer ownership to BB preparation.

Use the normal setup-managed Chezmoi operations to converge managed permissions:

- Initialization with apply, including each supported authentication path.
- Update-and-apply.
- Full apply.

Extend the existing subprocess-only, additive `umask go-w` approach. Preserve stricter caller masks, the caller shell's mask, native command arguments and error handling, and explicit Chezmoi configuration precedence. Do not rewrite configuration to force a different result.

This restriction affects all dotfiles managed by the affected operation, not only service directories. It is not a targeted chmod mechanism. Do not add a recursive permission sweep, take over unmanaged services, modify shell activation, or broaden the shared Node helper's existing files-only repair.

BB preflight remains read-only. Unmanaged writable files and explicit configurations that retain incompatible permissions remain blocked. Linked paths, ownership uncertainty, malformed metadata and existing process/service references retain their current protections. Preserve trusted system HOME aliases and existing safe service-link/mask handling.

## Diagnostics

Replace the generic-only preflight failure with a bounded, controlled account of safely inspectable blockers. Each diagnostic should identify:

- The operation that failed.
- A HOME-relative path when it can be represented safely, otherwise a controlled boundary/category label.
- The observed permission mode when known.
- A controlled reason, such as a writable boundary, unsafe ownership, linked managed metadata or unverifiable inspection.

Collect independent blockers only while inspection remains safe. Stop descending beneath an unsafe boundary; do not follow its children merely to produce a longer report. Bound both record count and total output size, and indicate when the report is incomplete. Escape or suppress unsafe path characters. A path outside HOME must not cause arbitrary custom paths to be dumped into the log.

Never print service contents, process arguments, credentials, raw stderr or arbitrary exception messages. The wrapper must reject malformed or unrecognized helper output and retain a generic failure fallback without echoing it. Failure must remain failure if diagnostic collection itself cannot complete.

Explain that explicit Chezmoi permission overrides and unmanaged paths require manual reconciliation; do not claim that a rerun necessarily resolves every blocker. Retain failure aggregation and log finalization while unrelated setup continues.

## Verification contract

All execution is confined to extracted functions, temporary homes and inert fixtures. Native Chezmoi integration uses a synthetic source with isolated configuration/state; no real dotfiles or source scripts run. BB entry points and service/lifecycle commands remain inert or forbidden.

Required evidence:

1. A regression reproduces both observed permission patterns through the actual preparation helper before the fix.
2. Native Chezmoi apply followed by real preparation preflight converges existing managed directories and service files, including repeated runs under inherited `0002` and newly created managed paths.
3. Actual call sites in all five scripts preserve arguments, errors, fallback executable selection and the caller's mask across initialization, update and full apply.
4. Stricter masks remain strict. Explicit conflicting Chezmoi policy is preserved and remains blocked rather than overridden.
5. Existing BB role deferrals receive no additional preparation-driven restriction. Ubuntu server protection, effective flag precedence and platform/headless behavior remain intact.
6. Unmanaged writable paths are preserved and remain failures. HOME, unrelated files, credentials, BB state, enrollment and services remain unchanged except for ordinary managed-dotfile convergence within the approved scope.
7. Unsafe ancestors stop descendant inspection. Independent safe branches can report multiple blockers; diagnostic limits, unsafe path characters, unknown helper output and secret sentinels are tested.
8. Existing safe service links, empty registrations and masks remain supported; unsafe links, references, ownership and metadata remain blocked. Shared helpers remain identical where required.

Run the BB preparation and server contracts, setup reliability, shared Node runtime and headless contracts, plus affected dotfile call-site regressions. Run Bash syntax checks, ShellCheck and documentation/whitespace checks. Use available PowerShell fixtures where the existing contracts support them, and explicitly report unavailable/native-platform coverage.

Update changed setup-script versions and README scope/recovery guidance during implementation. Native platform rollout remains separate from fixture validation.

## Boundaries and limitations

- No live setup, permission repair, package mutation, enrollment, service restart, provider authentication or Tailscale change is part of design or development.
- No weakening of preflight checks or conversion of an unverified safety failure into a warning-only success.
- No persistent Chezmoi configuration or dotfiles-repository change is included.
- Standalone or automatic dotfile applies can subsequently restore incompatible permissions; document this limitation rather than claiming persistent enforcement.
- Repository implementation was separately authorized after design approval. Live rollout still requires separate authorization and is not part of this task.
