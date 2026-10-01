# Fix three setup compatibility failures

Status: user-approved and implemented (TASK-63, TASK-61, TASK-62; Go was branch-local TASK-60 before collision resolution). The user subsequently requested publication to remote main. Integration preserves upstream `cf1ac23` and its concise README; compatibility details remain in code, tests, agent guidance and the validation record rather than restoring removed README sections. The integrated 25-suite contained matrix passes. Trusted Markdownlint remains unavailable and tasks remain In Progress for that validation gap. See [implementation and publication evidence](../research/2026-10-01-upstream-compatibility-validation.md). Publication is not authorization for native rollout.

## Scope and evidence

Fix the three reproducible defects associated with Ubuntu setup v286, commit `4bb7feb`, in `/home/scowalt/.local/log/machine-setup/2026-10-01-094452.log`. Apply shared fixes consistently to `mac.sh`, `ubuntu.sh`, `wsl.sh`, `pi.sh`, `bazzite.sh`, and `win.ps1`.

| Issue | Reproduced failure | Required outcome |
| --- | --- | --- |
| Pi Go catalog | Published Pi AI 0.99.2 uses a `chat:` catalog key; setup indexes the old unprefixed key. | Accept both verified catalog layouts without weakening model or credential checks. |
| Managed skills | Upstream removed `resolving-merge-conflicts`; setup still requires it. | Accept the reviewed current full suite while retaining historical ownership information. |
| OpenCode CLI | Official v2 formatting is `opencode v2.0.21`; setup requires bare `2.0.21`. | Accept the exact supported version formats, not arbitrary output containing a version. |

The investigation replayed real extracted helpers against public metadata and inert temporary fixtures. Changing only each implicated fixture input cleared its failure. Existing related contracts passed but did not cover these compatibility changes.

Public evidence:

- [Pi AI 0.99.2 package metadata](https://registry.npmjs.org/@earendil-works/pi-ai/0.99.2); the downloaded catalog matched the package's SHA-512 integrity.
- [Upstream skill retirement, September 24](https://github.com/mattpocock/skills/commit/daa01d8aa68ad5c61b68970ec2018d0ce9567be6), and reviewed [full-suite snapshot](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60).
- [OpenCode 2.0.21 source](https://github.com/anomalyco/opencode/tree/f46fa72a9285a0e8479e25d400f7026bfd8fe5c8): CLI runtime delegates version formatting to its pinned Effect 4.0.0-rc.112 dependency, whose `CliOutput.formatVersion` renders the command name, `v`, and version.

The log does not record the remote Pi AI dependency bytes, disposable skills report, or OpenCode probe stdout/status. These are reproducible code defects consistent with the log, not a complete native reproduction of that host.

### Boundaries

- BB server diagnosis and diagnostics are explicitly excluded.
- No live setup, fleet rollout, service restart, reboot, Tailscale changes, permission workaround, or remote cleanup.
- Never execute OpenCode, Pi extensions, installed skills, or model requests for validation.
- Preserve credentials, environment files, defaults, project data, npm policy, platform/headless gates, failure aggregation, and log finalization.
- Preserve ordinary provisioning behavior; do not reintroduce a maintenance switch.
- No broad refactor or new embedding framework. Use the existing OpenCode generator and existing identical-helper contracts for Go and skills.
- Do not modify or apply the separate dotfiles repository in this change.

## 1. Pi Go: support both catalog key layouts

### Implementation

1. Add permanent regression coverage in `tests/test_pi_opencode_go_setup.py` before changing the helper. Store a minimal public-data fixture with provenance for the Pi AI 0.99.2 Muse entry; tests must not download packages.
2. Update `installedPackages()` in the identical `PI_OPENCODE_GO_SETUP` blocks of all six scripts:
   - Keep scanning the catalog for exactly one model whose semantic `id` is `muse-spark-1.3-contributor`.
   - Accept that entry only in the `openai-responses` group under either the legacy ID key or `chat:` plus that exact ID.
   - Require `type: chat` for the new typed layout. Preserve compatibility with the older layout that lacks `type`; reject an explicit non-chat type.
   - Reject ambiguous duplicate entries, including simultaneous old/new aliases, unexpected groups, and arbitrary key spellings.
   - Retain exact checks for provider `opencode-go`, API `openai-responses`, base URL `https://opencode.ai/zen/go/v1`, reasoning support, and `thinkingLevelMap.xhigh === 'xhigh'`.
3. Leave file trust, permissions, native credential locking, active-profile selection, override rejection, and controlled error output unchanged. Do not import Pi runtime code to find the model.
4. Extend caller/wiring coverage to prove a compatible typed catalog no longer blocks subsequent Pi work, while a genuinely incompatible catalog still blocks it and contributes to the final failed result.

### Acceptance criteria

- Legacy and Pi 0.99.2 typed catalogs both succeed through the real extracted helper and applicable Bash/PowerShell wrappers.
- Missing, duplicate, incorrectly grouped, non-chat, wrong-provider/API/endpoint, non-reasoning, and wrong-xhigh entries still fail before credential mutation.
- Existing missing-key preservation, credential rotation, locking, custom-profile, and malformed/linked-metadata tests remain green.
- GPT-6 Astra defaults, other providers, and all unrelated credentials remain unchanged.
- All six embedded helpers remain identical.

## 2. Managed skills: refresh the baseline without losing history

### Implementation

1. Add a failing promotion regression to `tests/test_managed_skill_suite.py` using the reviewed upstream snapshot: all 37 current skills, including `pr`, but no `resolving-merge-conflicts`. Use inert `SKILL.md` files, complete matching copies, native-format JSON reports, and synthetic lock records.
2. Separate the required current baseline from historical managed names in the shared embedded policy:
   - Replace `resolving-merge-conflicts` with `pr` in the required baseline.
   - Retain `resolving-merge-conflicts` as a historical managed name for inventory, offline opt-out cleanup, and Pi duplicate exclusions, including machines without a previously written inventory.
   - Preserve existing copies during ordinary installation; upstream retirement alone will not introduce a new unconditional deletion rule. Existing ownership rules for identical versus modified direct Pi duplicates remain unchanged.
3. Update `tests/fixtures/matt-pocock-skills.json` and its upstream revision, adapting `tests/mock_managed_skills.py` and assertions where necessary. Keep current selection and historical cleanup expectations distinct.
4. Preserve full upstream discovery with `--skill '*' --full-depth --copy --yes --json`. Future names must remain accepted; the baseline is not an installation allowlist.
5. Preserve single-snapshot staging/promotion, both-copy validation, complete-report checks, destination preflight, lockfile merging, opt-outs, unrelated links, and bounded disposal.
6. Update README baseline/provenance wording and corresponding repository guidance. Avoid stale category counts; the old and current inventories both contain 37 names, so cardinality alone cannot validate the change.

### Acceptance criteria

- The complete reviewed current snapshot succeeds without recreating the removed upstream skill; `pr` and future upstream names are installed from the same verified snapshot.
- Omitting any still-required skill fails before destination mutation, even if an unrelated extra skill keeps the total count at 37.
- Invalid reports, partial copies, unsafe links, malformed metadata, and mismatched source records still fail.
- Historical `resolving-merge-conflicts` ownership survives inventory updates and remains covered by opt-out cleanup and Pi duplicate exclusions.
- Ordinary installation does not newly delete existing historical skill copies; unrelated skills and metadata remain unchanged.
- Both opt-outs, personal/work behavior, and all six identical embedded policies retain coverage.

## 3. OpenCode: recognize the official version output exactly

### Implementation

1. Add a failing regression in `tests/opencode-cli.test.cjs` that exercises the real `probe()` helper with inert native output `opencode v2.0.21`. Extend the existing isolated-environment probe fixture instead of running OpenCode.
2. Update `probe()` in `lib/opencode-cli.cjs` to accept only the expected bare release or `opencode v` followed by that exact release, after the existing surrounding-whitespace normalization.
3. Do not use substring matching, an unanchored semver search, arbitrary prefix removal, or general ANSI stripping. Retain `NO_COLOR=1`, isolated HOME/cwd/environment, timeout, output bound, and successful-process requirement.
4. Exercise installation paths as well as the direct probe: staged verification, already-current validation, and failure after promotion. Wrong output or process failure must retain/restore the prior command and receipt as required.
5. Regenerate the standalone scripts with `python3 tools/embed-opencode-cli.py`; verify with `--check`.
6. Keep existing controlled failure diagnostics. Broader diagnostic redesign is not required for this format fix, and raw stdout/stderr or arbitrary exceptions must not reach logs.

### Acceptance criteria

- Exact bare and official named version lines pass, including normal LF/CRLF endings.
- Wrong versions, prerelease/build suffixes not matching the expected stable release, wrong command names, empty output, multiple content lines, and extra text fail.
- Nonzero exit, timeout, signal termination, and output-limit failures remain failures even if captured output contains the expected version.
- Artifact identity verification still precedes every application version probe; unsupported/custom/pinned/newer-install behavior is unchanged.
- Failed staged verification does not displace an existing command; failure after promotion preserves the existing recovery contract.
- Generated copies and Bash/PowerShell caller contracts pass.

## Execution and verification

### Workflow

1. After approval, create or reuse three atomic Backlog tasks through the CLI, using the acceptance criteria above. Assign and mark each task In Progress before implementation; attach this plan and record its approval.
2. Work in the order above. For each issue, add the regression, record its contained red result, implement the smallest fix, and record green results before moving on.
3. Update each modified setup script's version and last-change description according to repository policy. If delivered as separate commits, each commit that changes a setup script gets its own increment. Update the OpenCode library header when changed.
4. Update README and any affected guidance alongside code. Self-review generated/shared blocks, safety boundaries, and failure propagation. Do not broaden scope to fix unrelated findings.

### Containment

Before behavioral execution, reread the [fixture audit](../research/2026-09-29-fixture-execution-audit.md) and [incident record](../research/2026-09-29-fixture-containment-incident.md). Use only definitions/helper extraction, temporary roots, and inert external commands installed before helper/caller execution.

Run suites sequentially through `tests/run-fixture-matrix.py` with a sanitized `env -i`, explicit existing runtime/tool paths, mandatory kernel filter/self-test, and private stdio. The following runtimes were present during planning; recheck before use:

```bash
env -i PATH=/usr/bin:/bin /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /tmp/pi-shared-runtime-pwsh.2SlAPL/pwsh \
  --tool-path /usr/bin:/bin \
  tests/setup-default-contract.sh \
  tests/test_fixture_containment.py \
  tests/pi-opencode-go-contract.sh \
  tests/opencode-go-wiring-contract.sh \
  tests/test_managed_skill_suite.py \
  tests/pi-skill-ownership-contract.sh \
  tests/simple-english-skill-contract.sh \
  tests/opencode-cli-contract.sh
```

Do not silently enable installed-code or cross-repository optional integrations. Copy native fixture runtimes where writable fixture prefixes are required; do not link them to real installations.

### Regression matrix and static checks

After focused red/green cycles, run the audited affected matrix under the same runner:

- AI-agent, model-default, shared-runtime, Pi package-maintenance, Pi profile-permissions, headless, and Telegram contracts.
- Setup reliability, weekly log regressions, Paseo non-management, pending-reboot, macOS CLT, and Homebrew-result contracts.
- The focused suites above, including current source extraction/containment and setup-default contracts.

Run `shellcheck` on modified Bash scripts, Bash syntax checks, available PowerShell parser checks, trusted installed Markdownlint on modified Markdown, generator consistency, and `git diff --check`. Do not fetch a new linter or runtime merely to run validation; report an unavailable tool.

Preserve test artifact paths, red/green output, source revisions, and skip counts in task notes. Optional native lock/catalog, skills CLI, npm shim, dotfiles, and unavailable native-tool coverage must be reported as skipped, not passed. Linux PowerShell tests are not native Windows verification.

### Completion and blocked conditions

Done means all three permanent regressions pass against the fixed production helpers, negative safety cases remain enforced, all six scripts are synchronized/versioned, affected documentation is updated, and the contained matrix/static checks pass or have explicitly documented blockers.

If containment or its preflight fails, or any real effect appears, stop immediately with the failing command, retained artifact path, and blocker; do not retry uncontained. If upstream evidence contradicts the supported schemas or version formats, stop for review rather than broadening acceptance heuristically.

No live rollout is included. A later, separately authorized machine run is needed to verify native behavior and determine whether the host has additional failures. BB's unresolved failure can still make that future overall setup run incomplete even after these three fixes.
