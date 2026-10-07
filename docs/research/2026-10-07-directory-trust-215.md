# #215: ordinary Pi ancestors, private Pi boundaries

Slice of #208, initially based on integration commit `75fc596b01d35a9ff3858be646d9b1df3cf4f16e`. Only Pi profile/Go trust helpers, their six embeddings, versions and Pi tests change. No tool versions, defaults, credentials, lifecycle authority or native Windows policy change. Group-access tampering remains an accepted risk, not a claim of exclusive ownership of the machine.

## Gate inventory

Names below identify the shared embedded code in all six entry points; Bash/PowerShell wrappers retain their existing result protocols.

| Gate / operation | Disposition | Evidence |
| --- | --- | --- |
| `PI_PROFILE_PERMISSIONS.unixPrepare.inspect`: HOME and ordinary selected-profile ancestors | **Changed**: real directories owned by the non-root target account allow group write, reject world write; do not chmod them | `test_group_writable_ordinary_ancestors_are_preserved_during_private_preparation`: 0750, 0755, 0775, 2775, six embeddings, repeated preparation; full metadata preservation |
| Same inspector: root/system/sticky temporary ancestors, target UID, no-follow/type checks | **Unchanged**: root remains strict with the existing sticky-root exception; foreign owners and links remain refused | `test_ordinary_group_write_requires_the_target_account_not_root_or_foreign`, existing foreign/world/link cases |
| `systemHomeAlias` in profile and Go helpers | **Unchanged**: only reviewed Linux `/home` alias with strict root-owned system parents | `test_only_the_trusted_system_home_alias_is_accepted` now prepares a real private leaf under 2775 HOME without changing HOME; Go alias controls retained |
| Profile managed set: `.pi`, `.pi/agent`, selected leaf | **Unchanged private contract**: preflight all profiles, prepare only these account-owned inodes to 0700, never recurse or repair ordinary ancestors | Arcane, selected creation, metadata preservation, two-profile preflight and unavailable-creation tests |
| Profile `unchanged`, parent pin and pre-chmod pin | **Retained/strengthened snapshots**: compare device, inode, full mode, UID and GID, including accepted-to-accepted changes | `test_accepted_ancestor_metadata_changes_fail_before_private_mutations`; mode, GID, UID, inode, type; existing parent replacement/disappearance cases |
| Profile `mkdirAt` capability/create/result | **Unchanged private contract**: isolated OS Python, descriptor-relative creation, owner/identity/result verification; unavailable capability fails closed | Existing creation-word, capability and parent-swap tests; no replacement privacy-proof interpreter |
| Profile `windowsPrepare` native owner/DACL/reparse/volume/file identity and pinned handles | **Unchanged** | Portable PowerShell wrapper, parser and C# compilation coverage; two native Windows tests skipped |
| Go `directoryChain`: ordinary HOME and eligible selected-profile ancestors | **Changed**: non-root account-owned directories permit group write; world/foreign/type/link checks remain; no group/process/ACL privacy proof | `test_group_writable_home_and_selected_ancestors_preserve_private_auth`: default, absolute selected and tilde selected, 0775/2775, every wrapper, preserved UID/GID/mode/inode/device |
| Go `directoryChain`: direct credential-writing profile | **Unchanged non-group/world-writable boundary**, now explicit at every profile preflight, creation, locked read and pre-write check | Existing profile-permissions failures in every wrapper; new private-leaf counterexample with accepted ordinary ancestors |
| Go installed package/dependency directory and regular-file inspection | **Already compatible** under existing installed-code/npm-umask allowance; scope, package identity, catalog and lock dependency verification unchanged, including pre-existing installed-code root allowance | `test_installed_npm_umask_does_not_relax_credential_permissions`, typed/catalog mismatch and dependency controls |
| Go `regular` / `readText`, environment parser and HOME owner | **Unchanged files**: ordinary metadata 0022, private input/auth 0077, installed-code 0002 masks; no-follow, hardlink, size and account checks retained | `test_writable_ancestors_do_not_authorize_other_owners_or_unsafe_files`, existing linked/public/malformed metadata and input-only tests |
| Go repeated directory inspection | **Strengthened stability**: retain device/inode/mode/UID/GID snapshots across native lock acquisition and credential publication | `test_accepted_ancestor_mode_and_group_changes_block_credential_publication`; all five race cases preserve auth and remove fixture locks |
| Go native credential lock, private temporary file and release/cleanup | **Unchanged**: same native dependency version/options/heartbeat, lock directory owner/type/world-write/empty checks, lock inode comparison, 0077 umask and exclusive 0600 credential temporary; no directory privacy-proof substitute | Existing refresh-under-lock, compromised/busy/release/rename failures, controlled diagnostics and cleanup cases; synthetic lock module only |
| Go Windows ACL owner/reparse/private-file/direct-parent checks | **Unchanged**; Unix group-write acceptance does not alter native ACL policy | Portable wrapper/legacy argument coverage only; no native Windows ACL claim |
| `PI_PROSE_RETIREMENT.safeDirectory`, installed package and JSON preflight, temporary replacement/revalidation/removal | **Already compatible**: no group-write predicate to remove; retain trusted HOME normalization, linked-directory/metadata refusal, verified package identity, unlink-only linked package and no npm/Pi/lifecycle execution | `test_retirement_and_repeat_preserve_unrelated_state` now retains 2775 HOME/npm/modules for both profiles; real caller also retires default/selected registrations while preserving custom prose/auth |
| `prepare_pi_mcp_adapter` / `Prepare-PiMcpAdapter` directory/store/resource/metadata checks and recovery | **Already compatible**: no directory mode refusal; keep links/types/hardlinks/JSON/pin/resource/activation validation and file-preserving temporary writes | `test_affected_custom_profile_recovers_idempotently`, `test_banned_adapter_removes_only_its_managed_records` now retain 2775 ordinary directories; real caller recovers and verifies the pinned adapter |
| `refresh_pi_packages` / `Update-PiPackages` profile/Git-container/checkout checks | **Already compatible**: no directory mode refusal; keep declarations, canonical Git identity, clean-checkout, redirection and offline checks | Real caller refresh through retained 2775 ancestors; existing clean/dirty/linked/malformed/redirection/failure cases |
| AskClaude package policy: profile ancestry, account/type/link checks, bounded metadata and atomic writes | **Already compatible**, no mode relaxation needed | Real caller retains the actual policy; AskClaude contract |
| CLI migration/noncanonical Bun cleanup, subagent/RPIV/legacy Ask User removals, bridge/companion/goal installs or exclusions, settings cleanup and autoresearch shortcut | **Already compatible**: no independent numeric/group-directory trust gate; retain runtime/profile/retirement/Go prerequisites and native package result checks | Package maintenance, companion, RPIV, subagent, AI-agent and shared-runtime contracts; commands inert |
| Model defaults, Synthetic retirement, z.ai model seeding | **Already compatible**: no ordinary-directory mode gate; existing file privacy and selected-profile semantics unchanged | Model-default and z.ai contracts |
| Ordinary caller prerequisite/failure/finalization gates | **Unchanged**: real privacy, retirement, credential and package failures block dependent mutations and survive unrelated work, reboot check and final logs | `test_real_caller_converges_private_pi_through_group_writable_ancestors` retains real profile/AskClaude/prose/Go/adapter/refresh operations; all six callers, both selections, repeat; Ubuntu/PowerShell counterexamples cover prior failure, world-write ancestor, public credential, malformed retirement/recovery, failed install, empty resource and failed refresh |

Already-compatible does not mean those helpers independently enforce every other component's policy. Their ordinary callers retain the bounded profile-preparation prerequisite. No blanket hardening or new managed locations were introduced. Non-package skill/resource and Backlog MCP retirement remain the separate #216 slice; managed skills, Impeccable and BB are not changed here.

## Containment and red/green evidence

Read the fixture execution audit and linked incident before execution. The new caller seam imports Bash **definitions only** and PowerShell top-level function ASTs, then installs inert unrelated operations before invoking the existing Pi caller tail and finalizer. Only temporary files and the fixture's inert Pi/npm commands and lock module run. Profile creation uses the existing isolated Python stdlib interface. Direct helper positives forbid child-process and group enumeration APIs when no creation is needed. Native runtime copies in the existing shared-runtime fixtures remain copies, not writable-prefix links. Optional installed-code integrations remain off. The kernel/FD filter is unchanged.

All behavioral commands used this serialized, sanitized prefix:

```sh
flock /tmp/setup-208-coordination/fixtures.lock env -i PATH=/usr/bin:/bin \
  /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /opt/microsoft/powershell/7/pwsh \
  --tool-path /usr/bin:/bin:/tmp/setup-208-coordination/tools
```

Append the exact suite arguments from this table. Artifacts contain private `results.json`, logs and mandatory successful kernel self-tests.

| Stage | Suite arguments | Artifact root / result |
| --- | --- | --- |
| Profile red, unchanged production | `tests/test_pi_profile_permissions.py` | `/tmp/setup-fixture-matrix-4w92alg_`: 12 failures, 0775/2775 refused as `failed:unsafe-ancestor` in all six embeddings |
| Profile green | same | `/tmp/setup-fixture-matrix-0utrv7wi`: pass |
| Go red | `tests/test_pi_opencode_go_setup.py tests/test_pi_package_maintenance.py` | `/tmp/setup-fixture-matrix-tudqvd9a`: Go 36 failures at `home:untrusted-directory`. Initial caller fixture had a truncated heredoc extraction, not policy evidence; corrected to definitions/AST imports before further caller claims |
| Real caller red | `tests/test_pi_package_maintenance.py tests/test_fixture_containment.py` | `/tmp/setup-fixture-matrix-0ea90mtr`: 12 caller failures at Go HOME trust, with unrelated work and failed log finalization retained; containment passes |
| Go and caller green | `tests/test_pi_opencode_go_setup.py tests/test_pi_package_maintenance.py` | `/tmp/setup-fixture-matrix-gc12lj1j`: both pass with original modes retained |
| Profile snapshot red | `tests/test_pi_profile_permissions.py` | `/tmp/setup-fixture-matrix-cpqoaita`: GID change incorrectly returned `prepared`; later subcases contaminated by that unexpected success were isolated before final validation |
| Profile snapshot green / Go snapshot red | `tests/test_pi_profile_permissions.py tests/test_pi_opencode_go_setup.py` | `/tmp/setup-fixture-matrix-c38i98bs`: profile passes; Go mode/GID/inode changes incorrectly succeeded. Each subcase now restores its fixture auth before running |
| Final focused contracts | `tests/pi-profile-permissions-contract.sh tests/pi-opencode-go-contract.sh tests/opencode-go-wiring-contract.sh tests/pi-package-maintenance-contract.sh tests/pi-prose-contract.sh` | `/tmp/setup-fixture-matrix-zi3i62ce`: **5/5 pass**, 24/27/5/31/22 test methods respectively, six explicit optional/native skips |
| Nearby matrix | `tests/setup-default-contract.sh tests/test_fixture_containment.py tests/shared-node-runtime-contract.sh tests/pi-model-defaults-contract.sh tests/ai-coding-agent-contract.sh tests/pi-askclaude-contract.sh tests/pi-companion-packages-contract.sh tests/pi-subagents-removal-contract.sh tests/pi-rpiv-removal-contract.sh tests/pi-zai-provider-contract.sh tests/pi-skill-ownership-contract.sh tests/simple-english-skill-contract.sh tests/headless-contract.sh tests/setup-reliability-contract.sh tests/weekly-log-audit-regressions.sh tests/pending-reboot-contract.sh` | `/tmp/setup-fixture-matrix-hsci0ty5`: **16/16 pass**, including environment/default, extraction/containment, PowerShell runtime/reliability, CLT and Homebrew-result coverage |

The initial parent setup-default/environment and containment baseline is `/tmp/setup-fixture-matrix-11ieec38`. Source-level Bash syntax, ShellCheck on all five changed Bash entry points, embedding equality and `git diff --check` pass. Versions increment in all six scripts.

## Limits and integration handoff

No containment preflight failure or unexpected real effect was observed; this is not a syscall-wide effects audit. Earlier incident uncertainty is unchanged. No installed Pi/extension/module, real credential, provider, native installer or live setup was executed. Native Windows ACL/handle tests, installed Go catalog/native lock interoperability, real registry adapter load and cross-repository dotfile integrations remain skipped. The broader tests likewise retain their optional native/installed-code skips. Linux PowerShell is not Windows verification; macOS/ARM/WSL/Bazzite and live usability require separate rollout evidence. Complete cross-component aggregate dispatch remains #217's responsibility.

Required #217 guidance reconciliation (do not remove historical evidence):

- Pi profile instructions: eligible non-root account-owned **ordinary** HOME/selected ancestors allow existing group access and are never permission-repaired. `.pi`, `.pi/agent` and the selected leaf still receive bounded private preparation. Mode/UID/GID/device/inode changes invalidate trust.
- Go instructions: distinguish ordinary ancestors from the **direct credential-writing profile**; private auth/input files, native lock semantics and Windows ACLs remain unchanged. Installed-code npm-umask tolerance already existed and is not a new regular-file allowance.
- Package/prose/AskClaude guidance: existing downstream directory validators already permit group write; keep the caller's profile prerequisite, metadata safety, offline retirement and exact pinned-adapter/resource contract. Do not describe these successes as permission to load extensions.
- Link this inventory from the final cross-component decision; record the accepted service-account group-access tampering risk without exclusive-group, private-ancestor, NSS, ACL or process-quiet proofs.
