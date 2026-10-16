# Beelink setup: BB snapshot refusal and Pi Go catalog incompatibility

## Scope and provenance

The initial investigation below changed no production code, remote files, packages, services, credentials or permissions. The subsequent local fixes and validation are recorded at the end. No live setup, BB application, Pi extension or model request was executed for validation.

- Watcher event: `setup-log-watch:2da1cb600696e9dabd476bad951914eb1df870272241b83b117976ff026c9428`.
- Exact [collector log](https://logs.scowalt.com/logs/scott-beelink-ubuntu/2026-10-16-03-25-00-834.log), retrieved with Doppler-backed bearer authentication: HTTP 200.
- Local run: `/home/scowalt/.local/log/machine-setup/2026-10-15-232426.log`, Ubuntu setup version 336. Checkout: `e913da1`, also version 336; matching version text alone does not prove deployed script-byte identity.
- Collector bytes and the independently read remote local log have the same SHA-256: `7d9450b5ec4f9519b9125a468117a72c894ce1442f1732048d9a0cb62f6eb6fa`.
- Trusted local Tailscale inventory identified online Linux node `scott-beelink-ubuntu`, node ID `nPLCnQkBsB21CNTRL`, address `100.73.203.69`. Read-only SSH used the repository's known account `scowalt`; the remote account, UID 1000 and hostname matched.
- Log and remote output were treated as data. Credential values were not requested; `.env.local` was inspected only for metadata. Raw log evidence remains private outside the repository. Quoted diagnostics below contain no credentials.

## Findings

### Confirmed: Pi 1.3.0's official Go endpoint fails setup's old URL predicate

Log lines 222–225 report successful Pi 1.3.0 installation and GPT-6 Astra defaults, followed by:

```text
Pi Go setup failed: go-catalog: catalog-incompatible.
```

The installed `@earendil-works/pi-ai` is also 1.3.0. Its Muse Spark 1.3 Contributor entry is typed `chat`, uses `openai-responses`, identifies provider `opencode-go`, enables reasoning and maps `xhigh` to `xhigh`. Its URL is **`https://opencode.ai/inference/go/v1`**. `installedPackages()` in `configure_pi_opencode_go` instead requires **`https://opencode.ai/zen/go/v1`** (`ubuntu.sh`, approximately lines 4600–4612).

The remote catalog hash is `39408ee6da7302e3202d7f7b27d31d4d50a05c340bebd7da25ee23755d506475`. It matches the catalog read without execution from the [official npm 1.3.0 artifact](https://registry.npmjs.org/@earendil-works/pi-ai/1.3.0). The tarball's SHA-512 integrity was checked against registry metadata before reading that single archive member; no archive was installed or extracted into a package directory.

The complete official catalog reproduces the same diagnostic through the extracted real Ubuntu wrapper, twice. Changing **only** that Muse entry's URL to the legacy value makes the same wrapper succeed. This is a setup/catalog compatibility defect, not evidence of a missing API key, an unsupported model, a broken `xhigh` mapping, or damaged installed package bytes. Existing fixture credentials remained byte-identical on the rejected path. No remote credential contents or inference behavior were tested.

All six scripts embed the same validator, so the compatibility issue is not Ubuntu-specific.

### BB: reproduced snapshot false positive; historical trigger strongly supported, not proven

Log lines 191–192 first verify the private TMPDIR override and reviewed environment reference. After a shared-Node readiness message, lines 194–195 report:

```text
BB server [preflight.app-unit]: service fragment or drop-in ownership is unverified.
BB server setup incomplete; review the BB server diagnostics above.
```

`setup_bb_server` captures the app customization snapshot, verifies it, performs intervening readiness/package checks, then verifies it again before mutation. `bb_tmpdir_snapshot` hashes each traversed object's device, inode, UID, GID, mode, link count, size, mtime and ctime, including the **contents-sensitive timestamps of the actively used TMPDIR**. A changed digest is reported through the generic unit-ownership diagnostic even when ownership, permissions, fragment bytes and loaded selection did not change.

Read-only observations:

- App/ingress unit files are account-owned, singly linked regular files, mode `0600`, with setup markers.
- The app has exactly the loaded `10-tmpdir.conf` and `20-env-local.conf` selections. Repeated `systemctl show` queries agree; ingress has no drop-ins.
- `20-env-local.conf` is mode `0664` with the exact reviewed reference bytes, permitted by ADR 0013. The TMPDIR override is `0600`; its target is account-owned `0700`.
- Six one-second-spaced metadata samples saw only `.cache/bb/tmp` mtime and ctime change among the monitored snapshot inputs. Its owner, group, mode, device, inode, link count and size stayed unchanged.
- Both managed services are currently `active/running`, with start times around **2026-10-15 18:52:55 EDT**, before the failed **23:24:26 EDT** setup. This is process-state evidence, not application/provider/browser readiness or proof of uninterrupted availability.

A contained replay through the real ordinary caller reproduces the same sequence and exact error when **only TMPDIR mtime** changes at the late preflight. Changing only ctime also reproduces it. Each variant fails twice, both with and without the reviewed environment reference. Keeping those timestamps constant reaches the inert pre-mutation gate. No ownership/permission change or unknown override is needed.

This establishes a reproducible false-positive mechanism and a strong candidate for the historical refusal. The original log contains no per-object snapshot diff, so it cannot prove which object/field changed in that run. Do not infer that an ownership violation actually occurred, or that chmod/chown would fix it. Preserve ADRs 0012–0014 and the private TMPDIR boundary.

### Cascades, recovery and other warnings

- Lines 199–200: plugin refresh was deferred because BB maintenance failed; “No verified local BB main server requires plugin refresh” does **not** establish recovery. No later BB maintenance success appears.
- Lines 226–230: `pi-profiles-blocked` and Impeccable preflight refusal follow the Go failure. The Ubuntu caller sets `PI_PROFILE_MUTATIONS_BLOCKED=1` on that failure, blocking subsequent Pi package work and these dependent operations. They are not evidence of a new profile-permission defect; line 202 already reports private Pi directories.
- The full Scowalt engineering suite succeeded earlier at line 207. Pi itself installed successfully; its subsequent Go configuration and dependent maintenance did not.
- APT explicitly labels the retained upgrades as **phased** (lines 41–50), not an unsuccessful package operation. No phasing override is warranted by this evidence.
- Tea's “already installed” warning is followed by verified readiness (lines 110–111). This is not a failed installation.
- The npm deprecation notice did not prevent Pi installation. The pending reboot is separate outstanding maintenance, not demonstrated to cause either reproduced failure.
- Line 241's incomplete-run outcome is justified. The run did not subsequently recover, even though the BB processes remain running.

## Feedback loop and validation

The temporary replay file was placed under `tests/` only for the audited runner, then retained in a clearly identified private debug location and removed from the checkout. It imports the existing fixture modules, uses definitions-only helpers, inert service/package operations, temporary homes and fixture credentials. No whole setup script is evaluated.

Already-run red command:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24/bin/node \
  --pwsh /usr/bin/pwsh --tool-path /usr/bin:/bin \
  tests/test_watch_2da1cb6_diagnosis.py
```

Corrected minimal red replay: `/tmp/setup-fixture-matrix-ofdf2bod`; 0.8 seconds, two tests with two failing repetitions each. Exact diagnostics match the log. The BB success assertion is arrival at the inert pre-mutation gate, not overall setup success: that gate deliberately refuses the subsequent directory mutation. An earlier draft incorrectly expected the gate's exit 73 to escape the production subshell; it was corrected to assert gate arrival and absence of the preflight diagnostic, then rerun red.

Differential replay: `/tmp/setup-fixture-matrix-_4a4r1t7`; two tests pass in 3.6 seconds by asserting the observed failures and one-variable positive controls. These passes confirm the diagnosis, **not a production fix**.

Initial investigation's final sequential contained matrix: `/tmp/setup-fixture-matrix-ehpjgwpg`, all six entries passed:

- `tests/setup-default-contract.sh`: 3 scheduling and 9 environment tests.
- `tests/test_fixture_containment.py`: 9 tests, including extraction/containment assertions.
- `tests/test_bb_service_preflight.py`: 35 tests.
- `tests/pi-opencode-go-contract.sh`: 27 reported, 2 optional installed-catalog/native-lock probes skipped; Linux PowerShell wrapper coverage was enabled.
- `tests/opencode-go-wiring-contract.sh`: 5 tests.
- Temporary differential replay: 2 tests.

The mandatory kernel socket-denial self-test passed. Existing suites' green status did not cover the missing timestamp-churn/1.3.0-endpoint regressions without the added replay. Native Windows/macOS behavior, live model access and BB readiness/continuity remained untested. This initial investigation did not claim a production fix or post-fix green result.

Private evidence and debug replays: `/tmp/setup-diagnosis-2da1cb6.pl9a6Y`. These temporary files are not durable repository artifacts; the bounded evidence above is retained here.

## Recommended follow-up at diagnosis time

1. Add the official 1.3.0 catalog as a credential-free regression fixture and narrowly update the shared Go endpoint contract in all six scripts. Continue rejecting paid Zen/arbitrary endpoints, model ambiguity and incompatible reasoning. Do not rewrite credentials or downgrade Pi as a diagnostic workaround.
2. Add the BB late-checkpoint timestamp-only regression, distinguish snapshot changes from ownership failures in diagnostics, and review directory snapshot semantics so routine child churn is not mistaken for identity/permission change. Retain UID/GID/mode/device/inode revalidation, file/content checks and private TMPDIR safeguards. The historical run's exact changed field remains unavailable.
3. Validate any implementation through the audited affected matrix, with version bumps for modified setup scripts. Production rollout, setup reruns, permission repair, service restarts and the pending reboot require separate authorization. No such action was taken here.

## Subsequent local fix, not rollout

After the owner requested fixes, all six embedded Go validators were updated to accept exactly the two verified Go URLs, retaining the provider/API/model/type/unique-match/reasoning checks. The new credential-free [1.3.0 fixture](../../tests/fixtures/pi-ai-1.3.0-muse.json) retains the exact published Muse entry; its equality with the integrity-verified public catalog was checked again. Wrapper tests cover credential preservation and repeat idempotency; caller tests exercise the current catalog instead of only the historical one. Paid Zen, alternate hosts, HTTP, query strings and unreviewed endpoint variants remain rejected.

BB now excludes only the reviewed private **TMPDIR target's** child-activity metadata (link count, size, mtime and ctime) from its snapshot. Device, inode, type, UID, GID, complete mode and exact `0700` privacy remain pinned at every inspection. Other directory snapshots, file/content checks and the complete ordered local/loaded drop-in selection are unchanged. Nothing enumerates or mutates TMPDIR children in production. Snapshot failures also receive the controlled `preflight.unit-snapshot` diagnostic instead of implying that a proven ownership violation occurred.

Permanent regressions exercise per-field churn both within inspection and between caller checkpoints, reject target identity/permission changes, and create a real child directory in a temporary fixture HOME between the complete logged caller's two snapshots. The latter completes inert stopped-update/readiness/plugin-refresh flow twice, preserving protected bytes and permissions. Its first red run had a fixture-only second-attempt cleanup problem after the expected first failure; cleanup was corrected before repeating the red/green loop.

Focused contained regressions: `/tmp/setup-fixture-matrix-1xvf5ind` went red before the production changes; `/tmp/setup-fixture-matrix-uc6mxxl4` passed all five tests after them (14.5 seconds). Both original diagnostics were reproduced before the fix; no failure was forced by editing production code. Script versions were incremented once: macOS 305, Ubuntu 337, WSL 261, Pi 278, Bazzite 182, Windows 198.

Final sequential contained matrix: `/tmp/setup-fixture-matrix-wj80onhp`, **21/21 entries passed**, 1,271.5 suite-seconds. The same sanitized runner, explicit native Node/PowerShell and mandatory kernel/FD self-test were used, with `--timeout 900` and a private command-selector directory for existing native mise/Chezmoi/Bun executables. No new tools were installed.

| Entries | Coverage |
| --- | --- |
| `setup-default-contract.sh`, `test_fixture_containment.py` | Ordinary dispatch/environment, extraction and containment |
| `bb-server-contract.sh`, `bb-machine-preparation-contract.sh`, `bb-plugin-refresh-contract.sh` | Complete server/customization/diagnostic/race matrix, preparation and refresh |
| `pi-opencode-go-contract.sh`, `opencode-go-wiring-contract.sh` | Legacy/current Go catalog, all six wrappers, dependent package gating and negative credential cases |
| `setup-reliability-contract.sh`, `shared-node-runtime-contract.sh`, `headless-contract.sh` | Failure aggregation/logging, runtime and platform/headless boundaries |
| `ai-coding-agent-contract.sh`, `pi-model-defaults-contract.sh`, `telegram-alerts-contract.sh` | Agent/default/environment regressions |
| `pi-profile-permissions-contract.sh`, `pi-package-maintenance-contract.sh` | Profile privacy and independent package/metadata safety |
| `pending-reboot-contract.sh`, `weekly-log-audit-regressions.sh`, `paseo-non-management-contract.sh`, `test_macos_clt.py`, `test_homebrew_results.py` | Reboot, weekly, unmanaged-tool and Apple caller/result contracts |
| Temporary focused replay, five tests | Re-ran the full published 1.3.0 catalog, all wrappers/callers and complete BB child-creation scenario after the fixes |

There were **11 reported skips**: optional installed Go catalog/native-lock, external-dotfiles/skills/registry integrations and native Windows profile ACL/handle cases. Linux PowerShell wrappers ran. Native platform behavior, live Go access and BB readiness/continuity remain unverified; offline success is not rollout evidence. The original log still cannot identify the exact historical snapshot field.

ShellCheck and Bash syntax passed for all five changed Bash entries; Python syntax, official fixture identity, Markdownlint, the repository no-comments policy and whitespace checks passed. Embedded Go equality is covered by its passing contract. A fixture-only portability correction avoids assuming that all Linux filesystems increment directory link count on child creation; the final focused replay includes that assertion. Source checksums and the removed temporary runner are retained under `/tmp/setup-beelink-fix.ify1g0`; permanent coverage remains in the existing four test modules and the new public fixture. No temporary test runner or debug instrumentation remains in the checkout.

No remote changes, setup rerun, service action, model request or native rollout was authorized or performed by these repository fixes.

## Publication rebase

Before publication, rebased onto remote main `8c7c7c0` (the BB/Pi trust and Visual Explainer Bash 3.2 heredoc repair). Preserved that upstream helper layout and both fixes here. The only conflicts were the five Bash version banners, advanced relative to the new main: macOS 306, Ubuntu 338, WSL 262, Pi 279, Bazzite 183; Windows remains 198.

The validation ledger above records the pre-rebase tree. Publication is additionally gated by the repository's complete contained pre-push contract hook, with explicit existing native tools and no optional live integrations. The hook's ShellCheck and Markdownlint commands use existing local tools rather than resolver-backed downloads. Native Bash 3.2 and platform rollout limitations remain unchanged.
