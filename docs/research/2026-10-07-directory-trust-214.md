# OpenCode account-directory trust (#214 / #208)

## Scope and gate inventory

Only OpenCode's canonical core, six generated embeddings/version banners and its existing offline fixtures change. No additional command locations, management interface, runtime dependency, flag or permission repair is introduced. The account identity remains the invoking target account (`process.getuid()`); account ownership does not authorize root-owned group write. Ordinary directories keep their UID, GID, mode and inode. Other principals already able to write them can still tamper with children; snapshots and verified bytes do not eliminate that accepted risk.

| Active gate / paths | Disposition | Behavioral evidence |
| --- | --- | --- |
| `safePath`: canonical HOME, `.local/bin` and receipt ancestors; recognized `.opencode/bin`, `.bun/bin`, npm/Bun/mise package containers, manifests and wrapper/native ancestors | Changed ordinary real account directories to reject world write, not group write. Regular files still reject `022`; ownership, link, type and HOME bounds remain. Root-owned group write remains refused, including a root invoking account. | `account-owned ordinary directories retain their modes…` installs, repeats and updates with 0700/0755/0775/02775 on Linux/Darwin fixture identities; npm/Bun/mise wrapper migrations retain package stores and all ancestor metadata; real five-Bash caller tests below. |
| `brewPermissions` + `inspectBrewCopy.inspect`: recognized command link, prefix, authorized ancestors, Cellar/keg/bin, receipt and optional pin path | Changed account-owned ordinary directories along already-recognized routes, including `/home/linuxbrew` outside the prefix. Preserved strict root/system-owned parents and foreign/world/link/type refusal. No prefix or command discovery expansion. | `recognized Homebrew migration accepts account-owned ancestors outside its prefix…`; existing Linux and both Darwin prefixes, absolute/relative links and revision matrix, current/newer/pin controls. |
| `brewPermissions`: regular files | Unchanged: only the existing account-owned Linux Homebrew file allowance permits group write. macOS files and files outside that Linux prefix remain strict. | 0664 Linux receipts survive migration unchanged; Darwin group-writable binary/receipt cases refuse; root/foreign/world-write/hardlinked receipt cases refuse. |
| `foreignCommand`: ownership-only external command classification and ancestor world/type checks | Already compatible. This filter neither identifies artifacts nor grants Homebrew/installation trust. Existing ownership boundaries and higher-priority foreign-command failure unchanged. | Lower-priority foreign trees retain contents/metadata; higher-priority foreign commands fail final selection without execution. |
| `safePath`/`checkAccountDirectories`; `checkBrewTrust`, `checkBrewBackup` | Preserve Homebrew snapshots. Extend account-directory snapshots through the same staging, quarantine, publication, current/newer selection and recovery boundaries so accepting a second mode cannot erase changed evidence. Parent-before-child comparisons retain dev/inode/UID/GID/mode/type; changed rollback boundaries retain private backup/lock evidence. | Twenty `account directory … change invalidates … evidence` cases (mode/GID/inode/UID/type at staged/promoted/current/recovery phases); Homebrew ancestor 0775→02775 and existing broad mode/group/identity/receipt/link/pin race matrix. |
| `boundedRead`; receipt/package/manifest readers; command-byte rechecks | Unchanged no-follow regular-file reads, size/identity checks, JSON validity/duplicate/pin checks, receipt hashes, official bytes, bounded discovery and native wrapper evidence. | Existing archive, metadata, pin, custom, shadowing and rollback regressions; added ordinary group-writable command and receipt refusal, failed inspection, linked command/ancestor and wrong-type controls. |
| `packageCommandDirectory`, `identify`, `commands`, `target` | Unchanged recognized locations, package names, versions, platforms/architectures and link forms. No inference from directory ownership to artifact identity. | npm/Bun/mise known wrapper migrations; custom/project-prefix, malformed release, unsupported architecture and custom binary preservation. |
| `verifySetupSelection`, `verifyFreshSelection`, executable access check | Unchanged actual command selection, alias/function/hash/shadow rejection, executable access, framed native evidence, newer preservation and Windows session selection. | Existing native fish with private inert profiles; Bash/PowerShell selection transaction and secret-safe diagnostic fixtures. |
| `probe`, `installChecked` staging/lock/recovery and receipt publication | Unchanged setup-owned mkdtemp/0700 lock/stage and 0600 receipt/journal boundaries, exclusive creation, staged bytes before probe, bounded rollback and cleanup. Only the existing setup-owned recovery directory chmod remains; input directories are never normalized. | Modes retained across install/update/current and failed probes; retained recovery directory is 0700; occupied-lock/destination and safe/unsafe rollback tests pass. |
| `Test-OpenCodeCliAcl`, Windows ACL approval and session protocol | Unchanged native owner/ACL/reparse protections. New POSIX directory snapshots are not applied on Windows. | Existing PowerShell wrappers, AST callers and simulated Windows native shim/selection transactions; native Windows ACL verification remains a rollout gap. |
| Bash/PowerShell wrappers, guarded Homebrew/APT upgrades, ordinary setup callers | Unchanged controlled result vocabulary, generic-upgrade exclusions, eligibility/headless gates, independent work, reboot and failure/log finalization. Existing diagnostics already avoid prescribing ordinary-directory chmod; no diagnostic relaxation needed. | Real extracted wrappers/core/caller tails install, migrate, update and repeat with mixed 0775/02775 HOME/ancestors, preserve unrelated sentinels, retain prior errors, and roll back an inert promoted-probe failure through finalization. |

Ordinary-directory fixtures forbid account/group inventory and proof-only filesystem/child-process operations rather than returning a successful privacy proof. Existing Homebrew fixtures cover shared/service memberships, unknown NSS, missing Python/proof paths and process churn with those operations forbidden. No live account/process inventory, app execution, network installer, credentials or machine permission changes were used.

## Red / green evidence

All behavioral runs used the shared `flock /tmp/setup-208-coordination/fixtures.lock` and the audited sanitized runner. Its C filter, FD checks and self-test are unchanged. The parent's initial default/environment/containment baseline was `/tmp/setup-fixture-matrix-11ieec38`.

| Cycle | Red artifact and failure | Green artifact |
| --- | --- | --- |
| Account directory install/repeat/update | `/tmp/setup-fixture-matrix-wtwtqxe9`: new real installer success case fails `unsafe-path` on unchanged production. Original group modes retained. | `/tmp/setup-fixture-matrix-30picw3y`: whole OpenCode contract passes. |
| Homebrew authorized ancestor | `/tmp/setup-fixture-matrix-nrw5l7yh`: real migration fails `brew-path` at original 02775 account-owned `/home/linuxbrew`. | `/tmp/setup-fixture-matrix-cdkbhi7b`: whole OpenCode contract passes. |
| Directory stability | `/tmp/setup-fixture-matrix-p4yt2ksj`: accepted-mode/GID/inode races incorrectly succeed; staged owner/type mutations migrate too far; recovery incorrectly restores through changed evidence. | `/tmp/setup-fixture-matrix-ztzv2k41`: whole OpenCode contract passes with directory snapshots. |
| Real callers | `/tmp/setup-fixture-matrix-9tyu9uo3`: restoring only the original `safePath` group-write gate makes five-platform fresh/migration/update cases fail `unsafe-path` through finalization; no input permission workaround. | `/tmp/setup-fixture-matrix-ht72i18t`: 13 caller methods pass, including unchanged PowerShell execution and new repeated-success/downstream-failure/prior-failure cases. |

The initial `/tmp/setup-fixture-matrix-x97b59zq` attempt failed a fixture assertion that selected the receipt instead of the recovery directory; it is not policy red evidence. Correcting only that selector yielded the genuine unchanged-production red above.

Exact command prefix for every run:

```sh
flock /tmp/setup-208-coordination/fixtures.lock env -i PATH=/usr/bin:/bin \
  /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /opt/microsoft/powershell/7/pwsh \
  --tool-path /usr/bin:/bin:/tmp/setup-208-coordination/tools
```

Each installer red/green uses the suffix `tests/opencode-cli-contract.sh`; caller red/green uses `tests/test_opencode_cli_callers.py`.

Expanded source validation at `/tmp/setup-fixture-matrix-qy5h4dll` uses `--timeout 600` followed by:

```text
tests/setup-default-contract.sh tests/test_fixture_containment.py
tests/opencode-cli-contract.sh tests/ai-coding-agent-contract.sh
tests/setup-reliability-contract.sh tests/headless-contract.sh
```

All six entries pass. OpenCode reports 419 Node tests (418 pass, one deliberate optional installed cmd-shim skip), five bounded captured-Mac preflight methods and 13 Bash/PowerShell caller methods. Default/environment: 3+7 methods; containment: nine; headless: seven. Reliability also executes CLT, Windows logging and Homebrew-result fixtures.

Nearby validation at `/tmp/setup-fixture-matrix-_gl2orcy` uses the same prefix and `--timeout 600`, followed by:

```text
tests/weekly-log-audit-regressions.sh tests/shared-node-runtime-contract.sh
tests/pi-opencode-go-contract.sh tests/opencode-go-wiring-contract.sh
tests/paseo-non-management-contract.sh tests/test_homebrew_results.py
tests/pending-reboot-contract.sh
```

All seven entries pass. Installed-code/dotfiles probes stay disabled: weekly managed-suite integrations skip three, runtime cross-repository integration skips one, Go native module/catalog integrations skip two, and Paseo cross-repository source verification skips one. No tools were installed; native writable Node fixture prefixes use existing copied runtimes.

Static verification: native `shellcheck mac.sh ubuntu.sh wsl.sh pi.sh bazzite.sh`, Bash syntax, `python3 tools/embed-opencode-cli.py --check`, actual PowerShell AST parsing in containment, and `git diff --check` pass. Source-only comment removal after the first expanded matrix did not change behavior. Final integration-tip merge/recheck evidence is recorded below.

## Integration recheck

Implementation commit: `cd80186`. Merged integration `73a8a9c` (BB preparation/server/refresh) with banner-only conflict resolution; the six-entry expanded command above passes again at `/tmp/setup-fixture-matrix-zl0u2axg` (merge commit `e109814`). Then merged the current integration tip `e23441a` (also Impeccable), again resolving only banners and regenerating OpenCode embeddings. The same runner prefix plus `--timeout 600 tests/setup-default-contract.sh tests/test_fixture_containment.py tests/opencode-cli-contract.sh` passes all three entries at `/tmp/setup-fixture-matrix-xcwwjan0`, with the same OpenCode counts/skips.

Final versions are macOS 287, Ubuntu 319, WSL 246, Pi 263, Bazzite 166 and Windows 185. Native ShellCheck, syntax/AST, whitespace, OpenCode embedding checks and integration BB-refresh/Impeccable embedding checks pass. The kernel/FD filter and runner remain byte-identical to the initial source. Native Gitleaks staged scanning also passes. Network-capable `bunx`/`uv` hooks were not invoked: native checks were run explicitly and commits used an empty hooks path. Markdownlint and the Python 3.14 comment-policy hook were not run here; no new source comments were added. Comparison against the merged integration tip shows only this ticket's core, fixtures, standalone blocks/banners and evidence file.

## Guidance for #217 and limits

- Supersede only the directory-scope limitations in ADRs 0005/0010 (and historical 0008); preserve ADR 0004's command-only migration and all regular-file/system/private/Windows distinctions. Preserve historical capture uncertainty.
- In CLAUDE.md's OpenCode Linux paragraph, replace prefix-only ordinary-directory wording with: “Accept otherwise eligible non-root account-owned real directories, including authorized ancestors, throughout existing recognized account and Homebrew routes. No group-privacy proof or permission repair is required. The existing Linux Homebrew regular-file allowance remains scoped to that prefix.”
- In its Darwin paragraph, replace Homebrew-prefix-only directory wording with the same recognized-account/authorized-ancestor rule. Keep root/system parents and regular files strict, parent-first traversal and mode/group/identity revalidation. Point both paragraphs to the cross-component #208 decision and this evidence; keep native Mac recovery unverified.
- No shared guidance, glossary or existing ADR was edited in this slice. No issue closure, push or live rollout was performed.
- Final repository-wide dispatcher and other tickets' BB/skills/retirement aggregates remain #217's responsibility. This slice ran its complete OpenCode contract and all nearby suites named above; it does not claim the full #208 aggregate.
- Linux-hosted Darwin/Windows simulations are not native macOS, Windows ACL/PowerShell 5.1, ARM, WSL or Bazzite rollout evidence. No actual OpenCode binary, installed application/skill/extension/plugin, native installer or provider request was executed. Existing containment incident uncertainty is unchanged.
