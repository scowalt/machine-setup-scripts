# bb desktop: Linux sandbox evidence and approved install-only contract

Date: 2026-09-28. TASK-49 parent-review follow-up (formerly TASK-48 before remote-main integration). The user approved verified installation with an unverified-launch compatibility warning ("Your spec is fine"). The implementation follows that decision; the findings below explain why launch compatibility is a separate rollout check.

## Findings

1. **The Ubuntu AppArmor flag is not a per-application denial result.** [Ubuntu 24.04 release notes](https://discourse.ubuntu.com/t/ubuntu-24-04-lts-noble-numbat-release-notes/39890) say the new default restricts unprivileged, unconfined applications. The default profile permits creating user namespaces but denies subsequent capabilities inside them. Applications can receive different permissions through matching AppArmor profiles, including a `userns` permission. The restriction first appeared in Ubuntu 23.10 without being enabled by default; 24.04 enabled it. Therefore `apparmor_restrict_unprivileged_userns=1` cannot establish that bb is denied, and `0` cannot prove every other sandbox prerequisite.
2. **The generic probe is also not bb's sandbox test.** [`unshare --user --map-root-user /usr/bin/true`](https://man7.org/linux/man-pages/man1/unshare.1.html) exercises that command in its own execution/security context. [Chromium's `Credentials::CanCreateProcessInNewUserNS`](https://raw.githubusercontent.com/chromium/chromium/main/sandbox/linux/services/credentials.cc) forks into a namespace, establishes UID/GID mappings, drops capabilities, then tests another unprivileged namespace operation. Different executable attachment rules, confinement, resource limits and the additional operations make the setup probe insufficient to prove Chromium's result. A failed probe likewise does not prove that a separately permitted bb context would fail.
3. **Extract-and-run solves FUSE, not the sandbox.** [bb's desktop README](https://github.com/get-bb/bb/blob/main/apps/desktop/README.md) recommends `--appimage-extract-and-run` when FUSE is absent. [AppImage's Electron troubleshooting guide](https://docs.appimage.org/user-guide/troubleshooting/electron-sandboxing.html) separately requires working unprivileged namespaces and specifically distinguishes Ubuntu before 24.04. It links the Ubuntu restriction change. Its suggested security-policy changes and sandbox-disable workaround are outside this task's authorization.
4. **There is no currently documented alternative official Linux desktop package in scope.** [bb's packaging configuration](https://github.com/get-bb/bb/blob/main/apps/desktop/electron-builder.config.json) targets Linux x64 AppImage. The desktop README describes a glibc-based distribution and Ubuntu 22.04 build baseline. The [Noble AppArmor package inventory](https://packages.ubuntu.com/noble/amd64/apparmor/filelist) lists many application profiles but no bb-specific profile. This is not proof that no applicable generic or locally installed profile exists on an individual host.
5. **Runtime paths are not restricted to `/tmp`.** [AppImage type2-runtime source](https://github.com/AppImage/type2-runtime/blob/main/src/runtime/runtime.c) reads `TMPDIR`, creates an `appimage_extracted_<digest>` directory or a `.mount_<name>` directory there, and exports an absolute `APPIMAGE` before executing `AppRun`. The mount prefix derives from the launch name, not a trustworthy application identity. Executable evidence plus the selected AppImage path is required; inherited `APPIMAGE` in a Node/Git/shell child alone is insufficient.

All sources were read publicly. No desktop executable, installed process inventory, security-policy change, native GUI probe or service operation was used for this investigation.

## Approved configuration matrix

| Configuration | Installation result / remaining verification |
| --- | --- |
| Ubuntu older than the glibc 2.35 baseline | Fails the required runtime-baseline check; no supported native launch claim |
| Ubuntu 22.04 x64 | Verified artifacts/menu can succeed with a compatibility warning; native GUI/sandbox launch remains unverified |
| Ubuntu 24.04 x64 with its default AppArmor restriction | Verified artifacts/menu can succeed with the same warning. The restriction is not read or used as an installation veto; launch may still need applicable per-app policy |
| Later eligible Ubuntu x64 with that restriction enabled | Same installation-only contract; no assertion that every release or configured host has identical defaults |
| Eligible Ubuntu with an existing application-specific policy | Policy is preserved without inspection or interpretation; verified installation succeeds with the warning, not a claim that the policy is sufficient |
| Eligible Ubuntu with missing/failing namespace-probe commands or unknown sandbox state | Those commands are not run or required; verified installation succeeds with the warning |
| Bazzite x64 with the supported runtime baseline | Same verified installation plus warning; native sandbox behavior remains policy-specific and untested |

All successful Linux installation, current-version verification and newer-version preservation results receive a controlled warning separating verified installation from untested GUI/sandbox compatibility. Running-app deferral is a distinct warning, not a successful update. Headless/unsupported skips remain separate and unchanged. Real digest, identity, runtime-baseline, path/ownership, process-safety, rollback and installation-verification failures still return failure.

Reading a profile file or a list of loaded profile names would not alone prove the effective attachment, permissions, included/local rules and execution transitions for the AppImage's runtime/extracted executable. Neither a host-wide flag nor a setup-process probe closes that evidence gap. This change does not attempt a partial AppArmor interpreter or use another application's profile as a workaround.

## Approved decision and implementation boundary

The parent asked whether verified Linux installation should count as successful with a compatibility warning, recommending that approach as consistent with the original installation-only scope. The user approved it on 2026-09-28. Unknown GUI/sandbox launch compatibility is therefore **not a failed required installation result**.

The former provisional global-AppArmor/generic-probe veto has been removed, not replaced with another proxy. Neither helper nor wrapper inspects this policy, runs a namespace or desktop-launch probe, or changes security policy to determine installation success. The helper emits one terminal result; the wrapper adds the compatibility warning only after an exact successful Linux result and zero status. Arbitrary extra helper output is still rejected. macOS signature/notarization validation and platform-specific reporting remain unchanged.

Setup-managed AppArmor exceptions, root/setuid helpers, global sysctl changes and `--no-sandbox` remain outside authorization. Manual native rollout must establish the real GUI/sandbox behavior on each intended machine before relying on the app; verified installation alone does not prove it will launch. If launch fails under the machine's security policy, investigate that policy separately rather than treating installation success as permission to bypass it.

## Process-inventory fix and verification

The process-inventory correction remains intact under the approved success contract:

- Same-account processes are classified by their executable before opening an environment. Verified unrelated executables remain unrelated even with a native-looking title or inherited `APPIMAGE`.
- Only credible desktop executables need environment inspection. An exact selected AppImage runtime/controller does not need it. Relevant unreadable executable/environment evidence, mixed/foreign owners, malformed evidence and identity changes fail closed.
- Stable foreign processes without a native desktop title are excluded before private executable/environment reads; native-looking foreign candidates are not silently exempted.
- PID start time, UID tuple, title and executable are rechecked. Normal running/sleeping scheduling transitions are not identity changes. An exited candidate is not reported as a running-app deferral.
- Mounted and extract-and-run paths support arbitrary absolute `TMPDIR` locations. Unknown desktop locations referring to the selected image fail rather than becoming safe deferrals.

Regression fixtures use only synthetic proc trees and inert artifacts. They cover the parent's exact inaccessible-unrelated-environment reproduction and the adjacent relevance, ownership, scheduling, executable-swap and exit cases. They do not establish native sandbox compatibility.
