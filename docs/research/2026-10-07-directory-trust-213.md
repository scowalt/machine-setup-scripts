# BB desktop directory trust — #213 / #208

## Scope and decision

Only desktop management changes. The identical `BB_DESKTOP_PAYLOAD` blocks in
`mac.sh`, `ubuntu.sh`, and `bazzite.sh` accept eligible account-owned ordinary
directories with group write; they do not repair modes or broaden destinations.
Initial versions advance 283→284, 314→315, and 162→163, respectively. WSL/Pi
wrappers and Windows remain unchanged. No CLI, enrollment, server, provider,
shell, project, or application execution is added.

Existing group writers, including service accounts, can replace children. This
accepts that residual tampering risk, not a claim of private groups or complete
race prevention. Independent ownership, world-write, file, artifact, native
identity and transaction checks remain necessary.

## Complete desktop gate inventory

The gate names below refer to the embedded Python payload unless noted. Evidence
is in `tests/test_bb_desktop.py` and `tests/test_bb_desktop_callers.py`.

| Gate / operation | Disposition | Named behavioral evidence |
| --- | --- | --- |
| `install_bb_desktop` exact headless/platform/architecture/Rosetta gates; Windows `Install-BbDesktop` | Unchanged eligibility, no permission-dependent platform expansion | `test_all_headless_and_supported_architecture_work_gates`, `test_apple_silicon_under_rosetta`, real-caller `test_exact_headless_skips_real_operation_with_unsafe_layout_untouched`, PowerShell AST wrapper |
| `install` root-account rejection; `trusted_home` account lookup and lexical HOME selection | Unchanged established non-root account identity; ordinary HOME traversal now accepts group write | `test_desktop_operation_rejects_root_account_before_any_external_effect`, `test_writable_ancestors_and_foreign_home_rejected`, real-caller mode matrix |
| `linux_home_alias` root-owned `/home` link and root-owned `/`, `/var`, `/var/home` mask `022` | Unchanged bounded Bazzite alias; no arbitrary realpath acceptance | `test_trusted_bazzite_alias_and_rejections`, `test_bazzite_xdg_alias_uses_resolved_home_only` |
| `checked_directory` / `directory` ancestor and leaf traversal | Changed: real non-root target-account directories reject `002`, not `022`. Root/system `022` and existing root-sticky exception unchanged; no proof or chmod. Missing authorized paths still created privately, parents checked first | `test_linux_group_writable_application_ancestors_install_update_and_current`, real-caller 0700/0755/0775/02775 matrix, `test_ordinary_directory_acceptance_does_not_authorize_foreign_or_root_group_write`, link/type controls |
| `checked_directory(..., macos=True)` native `/Applications` | Unchanged exact real root:admin GID 80, 0755/0775, native Darwin and explicit macOS context; no new system locations | `test_reported_root_admin_applications_updates_in_place`, `test_root_admin_parent_without_group_write_also_updates`, `test_nonstandard_applications_metadata_rejected_before_fetch`, `test_exception_requires_native_macos_and_explicit_mac_caller` |
| `install` application location selection, target-parent ownership, duplicate copies, Linux XDG boundary and `menu_text` | Already compatible once ordinary traversal accepts modes. Fresh Mac installs still `~/Applications`; existing verified system copy stays in place; selected XDG stays inside HOME | `test_system_app_absent_uses_user_directory_without_duplicate`, `test_ambiguous_copies_and_stale_linked_locks_are_preserved`, `test_group_writable_selected_xdg_directory_remains_supported`, `test_unsafe_xdg_and_menu_paths` |
| `regular`, `fingerprint`, `stable` | Unchanged account-owned regular-file `022`, single-link and no-follow/nonblocking fingerprint checks; containing ordinary directories use revised traversal | `test_group_writable_regular_artifacts_remain_refused`, `test_fifo_and_hardlinked_targets_fail_without_hang`, `test_linked_target_and_parent_fail`, `test_unmanaged_or_linked_menu_preserved` |
| `bundle` root and tree ownership/type/mode/link inspection | Changed: account-owned real directories use `002`; regular files retain `022`; bundle-contained framework links, foreign/root bundle refusal and native validation unchanged | `test_mac_group_writable_bundle_directories_current_and_update`, `test_system_parent_keeps_native_exception_with_group_writable_account_bundle`, `test_root_foreign_and_world_writable_bundles_still_refused`, file/link/signature controls |
| `bundle` plist identity/version/minimum OS/architecture/codesign/team/notarization | Unchanged official stable identity; never execute app | `test_mac_identity_signature_notarization_failure`, `test_mac_native_rejections_preserve_installed_bundle`, `test_system_nightly_custom_signature_and_signer_rejections_preserve_copy` |
| `fetch`, `Redirects`, `unique_json`, `release_asset`, `unpack_mac` | Unchanged bounded transport, official URL/digest/version/catalogue and archive type/traversal/link constraints | `test_bounded_transport_and_private_staging`, `test_release_metadata_matrix`, `test_redirect_rejects_untrusted_destinations`, `test_zip_traversal_and_links_rejected_before_extraction` |
| `installed_linux`, runtime check and menu verification | Unchanged official bytes, executable bit, newer/custom preservation, glibc baseline and verified menu; Linux success still explicitly does not establish GUI/sandbox compatibility | Install/current/newer tests, `test_nonexecutable_appimage_is_not_reported_current`, `test_custom_copy_fails_without_overwrite`, `test_old_glibc_fails_without_installation`, policy-noninspection tests and caller warning assertions |
| `running`, `linux_running`, `linux_process_snapshot`, `darwin_process_uid` | Unchanged operational process/owner identity, not a directory privacy proof; relevant uncertainty fails, verified running copy defers | Existing signed/unsigned UID, executable/UID/PID-change, foreign-process and running-at-promotion tests; `test_real_inventory_allows_install_and_update_with_unrelated_private_environment` now retains 0775 HOME/application parent |
| `directory_identity`, `capture_directories`, `boundary`, Mac `bundle_root_identity` | Extend existing native-system transaction snapshots to user application/menu ancestors and Mac user bundle roots. Device/inode/type/UID/GID/mode changes invalidate evidence even between accepted modes; no process/NSS/ACL privacy stabilization | `test_accepted_directory_metadata_changes_refuse_and_retain_recovery` (HOME, app parent, menu parent; six metadata changes), `test_mac_user_bundle_accepted_mode_change_cannot_defer`, existing native system-parent/target races |
| `private_boundary`, exclusive lock creation, `mkdtemp`, `transaction_ready` | Private contract retained/explicit on all paths: account-owned lock/stage with no group/other access. Native `/Applications` keeps exact 0700; user paths also allow inherited setgid 02700, which grants no group access. No ordinary directory normalized; unvalidated stage retained without traversal | `test_group_writable_lock_and_stage_are_not_ordinary_directories`, `test_private_lock_and_stage_accepted_mode_changes_retain_evidence`, `test_stale_lock_fails_closed`, native unverified/link-substituted stage tests |
| `unchanged`, `promote`, rollback and final cleanup | Existing artifact/menu/process rechecks, restore-on-failure and symlink-safe cleanup retained; all directory boundaries now revalidated before promotion/rollback/cleanup. Uncertain recovery retains lock/backup and failure | `test_menu_promotion_failure_rolls_back_both_objects` now uses 0775 parents, `test_post_install_verification_failure_rolls_back`, native failed-verification/unsafe-rollback/replaced-parent tests |
| `main` terminal protocol, Bash wrapper and ordinary callers | Unchanged controlled failure protocol, no arbitrary exception disclosure, independent failures retained through unrelated work, reboot and final result/logging | `test_main_does_not_echo_exception_details`, `test_outcomes_and_failures_aggregate_without_early_return`, real-caller `test_independent_and_real_desktop_failures_survive_reboot_and_final_logging` |

No directory-only proof infrastructure existed in this component to remove.
Acceptance tests forbid group/NSS enumeration, ACL reads, native subprocesses and
ordinary-directory chmod/chown while allowing only inert native identity replies
and the existing chmod of a newly downloaded Linux **file**. Process fixtures use
synthetic proc trees or inert `ps` responses, never a live inventory.

## Red → green evidence

Every behavioral command used this prefix, the shared lock, mandatory unchanged
kernel/FD filter/self-test, private stdio/roots and sequential suites:

```bash
flock /tmp/setup-208-coordination/fixtures.lock env -i PATH=/usr/bin:/bin \
  /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /opt/microsoft/powershell/7/pwsh \
  --tool-path /usr/bin:/bin:/tmp/setup-208-coordination/tools \
  <suite paths below>
```

| Vertical cycle / suite | Red artifact root | Green artifact root |
| --- | --- | --- |
| Linux real `install`, unchanged initial production, `tests/test_bb_desktop.py` | `/tmp/setup-fixture-matrix-ugit9u_0`: `unsafe-directory` at retained 02775 HOME | `/tmp/setup-fixture-matrix-o9dso2ld`: 102 methods pass |
| Mac real current/update, nested bundle gate, same suite | `/tmp/setup-fixture-matrix-_78090fl`: `unsafe-bundle-file` | `/tmp/setup-fixture-matrix-ux7r8yb3`: 103 methods pass |
| Accepted-to-accepted directory metadata race, same suite | `/tmp/setup-fixture-matrix-92cyngpr`: no refusal and old artifact replaced | `/tmp/setup-fixture-matrix-3zgl8e_u`: 104 methods pass |
| User Mac bundle accepted-mode change before deferral, same suite | `/tmp/setup-fixture-matrix-5nesz2z8`: no refusal | `/tmp/setup-fixture-matrix-e0oidx_k`: 105 methods pass |
| `tests/test_bb_desktop_callers.py`: extracted real callers + desktop wrapper + real operation, all three platforms | `/tmp/setup-fixture-matrix-2j9pkckv`: nine failures, `unsafe-directory` and `final:1`; 0700/0755 controls and headless skip pass | `/tmp/setup-fixture-matrix-5uzn21x7`: all three methods pass |
| Full desktop contract with safety controls and Windows AST wrapper | — | `/tmp/setup-fixture-matrix-pl9wr397` |

For the caller red run only, the three desktop payload blocks were temporarily
restored byte-for-byte from `git show 75fc596:mac.sh`, then restored to the slice's
green block. No unrelated component or other worktree was changed. The caller
fixture initially failed syntactic construction at `/tmp/setup-fixture-matrix-11czs4cv`;
that is **not policy red evidence**. It selected an unanchored embedded `main`
substring. The corrected fixture anchors top-level names and validates each
selected function with the existing reciprocal-delimiter validator before
execution. No production whole-file loader or containment guard was changed.

The caller adapter AST-loads only Python definitions, then installs inert fetch,
native command, process and account mocks before invoking the real management
operation from the real Bash caller. No installed native module, extension,
installer or application runs. Existing unaffected sentinels cover BB config,
credentials, service declarations, npm, environment, shell and nightly app data.

## Slice validation and limits

Initial-source default/environment and containment baseline was supplied by
parent at `/tmp/setup-fixture-matrix-11ieec38`. Slice affected matrix at
`/tmp/setup-fixture-matrix-y67rdzbh` passes **6/6 suites** in this order:

```text
tests/setup-default-contract.sh
tests/test_fixture_containment.py
tests/bb-desktop-contract.sh
tests/headless-contract.sh
tests/pending-reboot-contract.sh
tests/setup-reliability-contract.sh
```

Coverage: default wrapper 3 + environment 7 methods; extraction/containment 9;
desktop component 112 + callers 3 plus Windows wrapper; headless 7; reliability
includes CLT 10, Homebrew results 8 and PowerShell reliability. No skips reported
in that matrix. Pending-reboot is a static contract. ShellCheck, `bash -n`,
`git diff --check` and desktop embedding equality pass; the kernel filter is
byte-identical to initial `75fc596`. The final caller assertion also checks the
actual nonzero wrapper exit status; its refreshed desktop contract passes at
`/tmp/setup-fixture-matrix-991l6kzi` (112 component + 3 caller methods and Windows
wrapper). Static output is `/tmp/setup-208-coordination/213-static.log`, including
redacted staged Gitleaks with no leaks. Dependency-fetching pre-commit hooks are
not run; no Bun/uv dependency installation is authorized. Full configured
Markdown/comment-policy lint is left to final integration, not claimed here.

Parent #217 owns the complete cross-component aggregate and coherent guidance.
No claim of native Apple signature/ACL/menu/GUI behavior, Linux GUI/sandbox
compatibility, native Windows ACLs, ARM/WSL/Bazzite rollout or session continuity.
Optional installed-code integrations are off. Native runtimes were not installed
or linked into writable fixture prefixes. No real setup, permission repair,
service action, inventory, credentials or network request was used. This was not
a syscall-wide effects audit and does not alter the earlier containment incident's
remote-receipt/telemetry uncertainty.

## Integration refresh

Merged integration tip `e23441a` (Impeccable, preparation, server and refresh
slices) after implementation commit `8c57b6a`. Only the three version banners
conflicted; both components' helper changes were retained. Final merged banners
are macOS 287, Ubuntu 319, Bazzite 166. Desktop payloads were regenerated from
`mac.sh` into Ubuntu/Bazzite without replacing unrelated source. Relative to the
integration tip, only this slice's eight owned paths differ.

The same six-suite affected command above passes **6/6** again on the merged
source at `/tmp/setup-fixture-matrix-ywo5o9_r`, including all 112 component and 3
real-caller methods, Windows wrapper, CLT/Homebrew/reliability, headless and
containment/default coverage. No skips. Full cross-component aggregate remains
#217's obligation; these results do not substitute for it.

## Required guidance updates for #217

- Add the cross-component #208 decision pointer to the `CLAUDE.md` desktop bullet:
  ordinary account-owned HOME/application/menu/bundle directories permit group
  write without privacy proofs or chmod; files, root/system and private
  transaction boundaries remain distinct.
- Keep ADR 0006's native `/Applications` exception **exactly** root:admin 80,
  0755/0775, existing verified account-owned app, no fresh system install or
  relocation. Clarify that account-owned descendants/user destinations now follow
  #208 rather than being rejected solely for group write. Preserve historical
  evidence and the administrator-tampering risk.
- Record inherited setgid 02700 private user lock/stage handling: group/other
  access stays absent, while the native system-parent private mode stays 0700.
  Do not describe staging as ordinary or authorize private-credential changes.
- Keep Linux install-only compatibility warning and native-rollout limitations;
  do not add policy/namespace probes or claim that passing fixtures prove launch.
