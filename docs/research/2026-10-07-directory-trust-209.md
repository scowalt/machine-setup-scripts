# Impeccable ordinary-directory trust (#209 / #208)

Scope: Impeccable only, starting from integration commit `75fc596b01d35a9ff3858be646d9b1df3cf4f16e`. No live setup, installer, skill, extension, service, credential inspection or permission repair. Existing group access, including access held by service accounts, remains an accepted tampering risk, not proof of isolation. No location, account, provider or lifecycle authority is added.

## Gate inventory

All locations below refer to `lib/impeccable-skill.cjs`; both unchanged adapters embed this canonical policy into all six entry points.

| Gate / callers | Disposition and retained boundary | Behavioral evidence |
| --- | --- | --- |
| `directory`: recursive HOME, supported selected profiles, provider/skill/helper ancestors and temporary-root traversal | **Changed ordinary directories:** non-root target-account ownership accepts group write; world write, wrong type, foreign owner and arbitrary links still fail. Parent-first traversal remains. | `each_captured_directory_and_combined_layout…`, `root_system_boundary…`, `wrong_type_dangling_ancestor…` |
| `owned`: HOME, selected Claude/Codex profiles, destination containers, existing managed trees | **Changed directories only:** mask `002` for ordinary non-root account directories, `022` for regular files/root/private directories. No chmod/chown/ACL or privacy proof. | `readable_private_group_writable_and_setgid_containers…`, `ordinary_group_access_does_not_weaken_files…` |
| `context`: default `.pi`, default Pi profile and active selected Pi profile | **Unchanged private write boundary:** explicitly retain the prior `022` write refusal rather than inheriting the ordinary-directory allowance. The separate profile preparer still owns exact `0700` preparation; Impeccable neither repairs nor claims to replace it. Generic selected-profile ancestors and `skills` children are ordinary. | `private_pi_boundaries_still_refuse_group_write…`; profile-permission contract; six-caller blocked-profile cases |
| `context`: `blocked`, absolute path, active Pi within HOME, profile collisions | **Unchanged authorization:** blocked profiles fail before mutation; supported selected destinations only; no new path eligibility. | blocked-profile, outside-profile and profile-collision regressions |
| `directory`: privileged/root ancestors and sticky-root exception | **Unchanged system rule:** root group/world-write rejection and existing root-sticky exception; no general account allowance for UID 0. | `root_system_boundary…` includes root-owned 0755 success / 0775 refusal; ordinary fixtures traverse existing sticky temp root |
| `systemHomeAlias` | **Unchanged system exception:** Linux `/home` alias accepts only the existing root-owned `/var/home` shape with strict system modes. | `trusted_bazzite_home_alias…` positive and foreign/writable-system controls |
| `jsonFile`, `readRegular`, `jsonChange` | **Unchanged files:** account ownership, `022` refusal, regular/no-follow/single-link checks, size bounds, parsing and opened-file identity; existing metadata mode preservation. Their ordinary parent traversal now accepts group write. | file/metadata group-write, hardlink, malformed inventory/settings, changed-selection and rollback cases |
| `copiedTree`, `removable`, `remove` | **Changed through directory-aware `owned`:** managed directories can have group access during validation, update and offline exclusion. File rules, types and bounded no-follow traversal remain; exclusion still unlinks authorized leaf links without following them. | individual/combined lifecycle cases, selected/setgid cases, malformed payloads and linked exclusion sentinels |
| `ensureDirectory`, `copySnapshot` | **Already compatible creation contract:** leave existing containers' UID/GID/mode unchanged; new parents remain 0700; copied verified payload retains existing copying semantics. Replacement of an owned payload is still a transaction, not preservation of that payload's inode. | metadata assertions through install/update/repeat/exclude/reinstall; failed-promotion rollback |
| `fingerprint` | **Revalidation strengthened:** retain inode/type/mode/content checks and also snapshot UID/GID, including nested artifact directories, so an accepted group change cannot disappear from evidence. | `accepted_metadata_changes_in_destinations_and_ancestors…`; second red/green cycle below |
| `snapshotDirectories`, `unchangedDirectories`, transaction `recheckParents` | **Unchanged stable-evidence rule:** compare device/inode/type/UID/GID/mode even when both modes would independently be accepted. | accepted 0775→0770, GID, inode and owner changes before promotion; parent mode change during failed promotion |
| `transaction`: lock, publication, rollback, pending recovery | **Unchanged private/recovery contract:** exclusive 0600 lock, staged verification before rename, verified prior-state restoration, no success on uncertain rollback, retained backup/lock evidence and refusal of a subsequent run. | `accepted_parent_changes_during_failed_promotion…`, `replacement_rolls_back_every_provider…`, cleanup-failure recovery cases |
| `stagePath`, `run(stage/promote/dispose)` | **Unchanged private stage:** bounded native temporary-root/name, private stage root (`077` rejection), private child creation and bounded unlink disposal. Only eligible ordinary temporary-root ancestors gain group tolerance. | `ordinary_group_access_does_not_weaken_files…` unsafe-stage case; installer isolation and stage-leaf-link cases |
| `windowsRecord`, `windowsTrust` | **Unchanged native ACL/reparse policy:** same pinned-handle program, owner/access/identity/ACL comparisons and controlled refusal. No POSIX allowance is applied to native ACLs. | unchanged source plus Windows-uncertainty refusal and portable PowerShell adapter/caller coverage; native Windows unverified |
| `nativeTarget`, `validateSkill`, `skillIdentity`, `engineChecksum`, `payloadDigest`, `sameTree` | **Unchanged required artifact gates:** supported platform, complete five-provider snapshot/helper resources, identity, executable bits, pinned official checksum URL/bytes, unchanged source and managed Pi content. Ordinary tree directories use the revised rule; file and payload verification do not weaken. | complete payload assertions in six real callers; malformed/missing/corrupt/unavailable/modified payload controls |
| `matchesSkill`, `enabledSkill`, `ignoredPiDescriptor`, `discoveryIntent`, inventory validation | **Unchanged discovery/ownership gates:** verify native Pi discovery input and resource selection, preserve custom content, owned exclusions only. Ordinary parents accepted; metadata stays strict. | selected/default caller convergence, ignore/glob/override cases and offline exclusion metadata assertions |
| Bash/PowerShell adapters and ordinary caller result gates | **Unchanged runtime/npm/result contract:** exact opt-out, runtime/npm prerequisites, one isolated installer snapshot, environment restoration, no hooks, independent work/reboot/final logging and retained earlier errors. | all six real callers retain the real Impeccable operation; installer/runtime/verification/promotion/earlier-error cases now run with captured group-writable containers |

Test names above abbreviate the `test_` methods in `tests/test_impeccable_convergence.py` and `tests/test_impeccable_callers.py`; they execute the real public convergence operation, not permission predicates.

The nine captured directories are `.agents`, `.claude/skills`, `.agents/skills`, `.cursor`, `.cursor/skills`, `.gemini`, `.gemini/skills`, `.pi/agent/skills`, and `.cursor/agents`. Each is tested alone and together at 0775 with HOME 0750 and Pi boundaries 0700, through fresh install, update, repeat, exact offline exclusion/repeat and reinstall. UID/GID/mode stay unchanged throughout each operation. Additional 0700/0755/0775/2775 controls cover HOME, multiple selected ancestors, external supported Claude profiles and default/selected Codex retirement containers. Tests forbid Unix child-process/group/account/proc privacy inspection and policy permission repair at the existing external boundary. Synthetic nonprivate ancestor/shared GID metadata avoids making the real fixture root nonprivate.

## Red/green and validation

Every behavioral command uses this same prefix (including the shared cross-worktree lock):

```bash
flock /tmp/setup-208-coordination/fixtures.lock env -i PATH=/usr/bin:/bin \
  /usr/bin/python3 -I tests/run-fixture-matrix.py \
  --node /home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node \
  --pwsh /opt/microsoft/powershell/7/pwsh \
  --tool-path /usr/bin:/bin:/tmp/setup-208-coordination/tools
```

| Artifact root | Suffix / source stage | Result |
| --- | --- | --- |
| `/tmp/setup-fixture-matrix-dozjtra8` | `tests/impeccable-callers-contract.sh`, unchanged production | **Red:** 9 methods, only new Ubuntu captured-layout success assertion fails with `Impeccable: unsafe-owner-or-mode`; final setup incomplete. |
| `/tmp/setup-fixture-matrix-w06iz0ey` | Same suffix, ordinary-directory gate change | **Green:** 9 methods, no skips; captured-layout caller verifies all providers and finalizes successfully without mode repair. |
| `/tmp/setup-fixture-matrix-144xw26h` | `--timeout 900 tests/impeccable-skill-contract.sh`, before fingerprint repair | **Red:** 33 methods, only new nested-directory GID-race refusal fails because old fingerprint incorrectly reports verified success. |
| `/tmp/setup-fixture-matrix-pnwa2uye` | `--timeout 900 tests/impeccable-skill-contract.sh tests/impeccable-callers-contract.sh`, UID/GID fingerprint repair | **Green:** convergence 33 + embedding 1 + callers 9, no skips. |
| `/tmp/setup-fixture-matrix-qd2sb7nx` | `--timeout 900 tests/setup-default-contract.sh tests/test_fixture_containment.py tests/impeccable-skill-contract.sh tests/impeccable-callers-contract.sh`, added refusal/recovery controls | **Green:** all four entries; convergence 37 methods. |
| `/tmp/setup-fixture-matrix-o29w3p2x` | `--timeout 900 tests/impeccable-skill-contract.sh`, private-boundary audit regression | **Red:** six cases in one new method reveal that the first generalization also accepted group-write on explicitly private Pi boundaries. |
| `/tmp/setup-fixture-matrix-w6rzc8ty` | `--timeout 900 tests/setup-default-contract.sh tests/test_fixture_containment.py tests/impeccable-skill-contract.sh tests/impeccable-callers-contract.sh tests/pi-profile-permissions-contract.sh`, final slice policy | **Green:** 5/5 entries. Default/environment 3+7 methods; extraction/containment 9; convergence 38 + embedding 1; real callers 9; Pi profiles 21 with 2 native-Windows skips. |

Nearby matrix `/tmp/setup-fixture-matrix-dn4vrzwn`, run after the ordinary-directory/fingerprint changes and before the explicit-private-boundary audit repair, passed **9/9 entries** with suffix:

```bash
--timeout 900 \
  tests/pi-skill-ownership-contract.sh tests/simple-english-skill-contract.sh \
  tests/pi-profile-permissions-contract.sh tests/shared-node-runtime-contract.sh \
  tests/pi-opencode-go-contract.sh tests/pi-package-maintenance-contract.sh \
  tests/setup-reliability-contract.sh tests/weekly-log-audit-regressions.sh \
  tests/headless-contract.sh
```

Explicit skips: Pi profiles 2 native Windows ACL/handle cases; runtime 1 cross-repository dotfiles integration; Go 2 installed catalog/native-lock integrations; Pi package maintenance 2 registry/dotfiles integrations; weekly managed suite 3 installed skills-CLI/dotfiles integrations (32 methods, 29 executed). Runtime's 18 ordinary tests and both PowerShell modes passed; Go 24 methods, package maintenance 30, headless 7. The profile suite was rerun on final policy as recorded above. Optional installed-code flags remained absent; nothing was installed to fill a gap.

Static checks: six embedding equality, Node syntax, all five modified Bash syntax/ShellCheck, whitespace, and PowerShell AST parse pass. All six setup banners incremented. Canonical Bash/PowerShell adapters, extraction helpers, runner and mandatory C filter are unchanged. Filter SHA-256: `1963233f54482e9fc8e0cdaf2ee7696e4ff4fdc09f42e96f72f4e713d1d0629f`.

## Limits and handoff to #217

The final complete pre-push dispatcher/cross-component aggregate belongs to #217, including merged BB/OpenCode/retirement/AI-agent/reboot/CLT/Homebrew coverage and standalone Windows reliability. This slice has not claimed that aggregate. Tests use inert official-shaped artifacts and synthetic metadata, not live native setup, actual elevated account dispatch, native Apple/Windows/ARM/WSL/Bazzite readiness or usable skills. No containment refusal or unexpected real effect was observed; this is not a syscall-wide effects audit. The historical fixture incident and collector/telemetry uncertainty remain unchanged.

Required guidance update for #217 (do not edit shared guidance piecemeal): add to the current Impeccable paragraph, “Accept otherwise eligible non-root account-owned ordinary Unix directories with group write at HOME, supported profile ancestors, provider/skill/helper containers and managed trees. Preserve their existing UID/GID/mode; do not require group privacy or repair permissions. Keep file/system/native-ACL rules, explicitly private Pi profile write boundaries and private staging/recovery safeguards. Retain UID/GID/mode identity revalidation even between accepted states.” Link the cross-component accepted-risk decision and this evidence. Do not imply that directory acceptance overrides the independent Pi permission preparer or authorizes another profile/location. Existing README and historical ADRs were not edited by this slice.
