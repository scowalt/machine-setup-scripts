# TASK-43: Windows WinGet retirement inventory research

## Decision summary

**Do not replace the optional cmdlet with an exit-code-only `winget list` / `uninstall` / `list` sequence.** Microsoft explicitly makes source-search failures nonfatal in both commands. A failed search can produce the same “no applications found” HRESULT as an empty successful search. This is a specific fail-closed blocker, not a need to inventory every manually downloaded application.

**PS7 plus Microsoft.WinGet.Client, or manual-only retirement, is not an established exhaustive choice.** App Installer ships a native COM/WinRT API and metadata; WinGet portable packages also have narrowly identifiable native registry records readable through Windows PowerShell 5.1's existing .NET Framework. Those alternatives need a bounded design and native Windows validation, not an assumed new runtime requirement.

**A separate identity discrepancy needs resolution:** the repository's original command names `Infisical.CLI`, but Microsoft's inspected official manifests name **`infisical.infisical`** and describe ZIP/portable installers. Do not silently substitute or add that ID to the approved removal scope. [M1], [M2]

This is research/design advice only. The approved retirement plan, implementation, tests, and task records are unchanged.

## Evidence baseline

Source links below pin Microsoft WinGet CLI release **v1.29.380**, commit `000f6b55151cb0f1afd2933bb54c62a4724b9ca8`. The decisive warning behavior also exists in **v1.12.350**, commit `95add984d147223256630f762824f768d98d9485`; it is not merely an unreleased change. Current master `5e96f4fa76840778c756162326fb65ce70623a24` was cross-checked for the same behavior. No claim is made that every historical client supports every option. [S1], [S2], [S3]

## Proposed native sequence: what it actually proves

These are the commands assessed, **not commands executed or an approved implementation**:

```powershell
winget list --id Infisical.CLI --exact --source winget --accept-source-agreements --disable-interactivity
winget uninstall --id Infisical.CLI --exact --source winget --silent --preserve --accept-source-agreements --disable-interactivity
# Repeat the identical list command as a postcheck.
```

Microsoft documents the ID, exact-match, and source options. `--exact` is case-sensitive. `list` includes applications installed by means other than WinGet. The uninstall documentation explicitly supports removing such applications too. Therefore a source correlation is not proof that setup, or even WinGet, originally installed an application. [D1], [D2]

### Exit classification

| Result | Meaning supported by source | Retirement classification without independent inventory |
| --- | --- | --- |
| `list`: `0` | The composite search passed its nonempty-match check. Not a uniqueness or failure-free-search guarantee. | Candidate evidence only; insufficient authorization. |
| `list`: `0x8A150014` / signed `-1978335212` / unsigned `2316632084` | `APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND`: composite search returned zero matches. | **Not independently verified absence**, because source failures may already have been downgraded. |
| `uninstall`: `0x8A150016` / signed `-1978335210` | `APPINSTALLER_CLI_ERROR_MULTIPLE_APPLICATIONS_FOUND`. | Ambiguous; fail, preserve, no narrowing by guesses. |
| `uninstall`: `0` | Native uninstall workflow reported success. | Require independently verified post-removal absence. |
| Any other nonzero, invocation exception, timeout, unavailable/unparseable result | Error or unverified execution. | Fail; never reinterpret as absence. |

There is no separate `APPINSTALLER_CLI_ERROR_NO_PACKAGES_FOUND` alternative in the inspected error definitions. “No packages found” is the description of `NO_APPLICATIONS_FOUND`; neither that description nor a localized message is a second trustworthy absence signal. Capture the native exit status immediately and normalize its 32-bit representation when comparing signed/unsigned values. [S4], [S5], [S30]

### Why the exact query still fails closed-policy requirements

1. **Partial search failure is deliberately tolerated.** `ListCommand::ExecuteInternal` and `UninstallCommand::ExecuteInternal` set `TreatSourceFailuresAsWarning`. `HandleSearchResultFailures` then prints warnings without setting a failure HRESULT. `EnsureMatchesFromSearchResult` subsequently returns `0x8A150014` when the remaining matches are empty. [S1], [S2], [S5], [S30]

   A concrete code-path counterexample: an installed ARP package has a local ID such as `ARP\machine\x64\<product-code>`, not the repository's `Infisical.CLI`. Exact local-ID lookup finds nothing; the available-source search needed to correlate the repository ID fails; the composite accumulates that failure; `list` warns and returns “no applications found.” The source implements both the generated ARP ID and exception-to-search-failure conversion. One selected source is enough; unrelated Store sources are not needed for this failure. [S6], [S7], [S21]

2. **A successful open does not prove a fresh index.** Source opening attempts eligible background updates, catches update errors, and can continue using the cached source. `OpenNamedSource` only warns about those update failures. An absent result is therefore not proof against a source that never acquired the needed metadata or lost the relevant correlation. Conversely, offline operation does not invalidate independently verified local native ownership. Adding `winget source update --name winget` and trusting its exit code is not a fix: its workflow also has unsuccessful-update paths that only print status. [S8], [S9], [S22]

3. **`--source` selects available-source correlation, not historical ownership.** The composite still incorporates installed-only matches. Current `ReportListResult` filters uncorrelated *display rows*, after the nonempty-match check; an empty displayed table does not itself change the exit HRESULT. `uninstall` does not run that list-formatting filter. Thus do not promote “exit 0” into “one displayed, source-verified official installation,” or assume `uninstall` enforces the display rule. Correlation uses native references such as product codes/package-family names and, in some cases, normalized name/publisher. Custom/unmatched installations must not become removal targets merely because a display name resembles Infisical. [S21], [S30], [S31]

4. **Source name is configuration, not identity.** Before relying on `--source winget`, a prospective implementation can use the documented, JSON-producing `winget source export --name winget`. Require exactly one well-formed record with `Name=winget`, `Type=Microsoft.PreIndexed.Package`, `Arg=https://cdn.winget.microsoft.com/cache`, and `Identifier`/`Data=Microsoft.Winget.Source_8wekyb3d8bbwe`. Missing, substituted, ambiguous, or unsupported output fails closed. This is a normal configured-source check, not protection against arbitrary privileged attackers. It verifies configuration, **not** index freshness or search completeness. Do not reset/add/remove sources. [D3], [S10]

5. **Agreements and errors remain distinct.** `--accept-source-agreements` avoids that source's agreement prompt; `--disable-interactivity` avoids unattended prompts. An unaccepted agreement is `0x8A150046`, not absence. Missing source name (`0x8A150012`), missing data (`0x8A15000F`), open/network/policy errors, and unsupported flags all fail. Explicit `--source winget` avoids asking unrelated sources, but does not make the selected source's failures fatal. Warnings share the reporter output stream with ordinary output; “empty stderr” is not a locale-independent success check. [D3], [S4], [S8], [S11]

### Multiple matches, installers, and preservation

- `list` intentionally permits multiple matches. `uninstall` requires one composite package; multiple installed versions without a version selector or `--all-versions` also return `0x8A150016`. Do not add `--all`, `--all-versions`, an arbitrary version/scope, or a retry-until-empty loop to evade ambiguity. Preflight each independently authorized native identity instead. [S30], [S12]
- WinGet selects the uninstall mechanism from **installed metadata** (MSI, EXE, portable, etc.). It is not inherently a portable-only remover. An MSI manually installed outside WinGet may correlate with an official manifest; this alone does not establish the approved managed footprint. User/machine scope and multiple native registrations need explicit treatment. Recent source also prohibits elevated uninstall of some user-scope installers, including portable: fail and report rather than adding privilege tricks. [S12]
- Use **`--preserve`** for an authorized portable uninstall. Omitting `--purge` is insufficient: the user's `uninstall.purgePortablePackage` setting can request directory purging unless `--preserve` overrides it. Never use `--force`; native portable removal normally rejects unexpected file/hash state. Preserve credentials, projects, custom copies, and unrelated packages; do not delete files or execute registry uninstall strings yourself. [D2], [S13]

## Does export solve the narrower problem?

**Omitting unrelated manual applications is not, by itself, a blocker.** They are outside the managed footprint. A valid export containing the exact ID and validated source identity is useful positive correlation evidence.

But an empty/missing entry is not a complete negative result even for that narrow footprint: `export` also sets `TreatSourceFailuresAsWarning`, and `SelectVersionsToExport` skips installed packages for which it cannot obtain an available version. A formerly managed package can become unexportable when source/correlation data is unavailable. Export cannot distinguish that state from absence, and does not reliably represent every distinct installed variant. Do not accept empty export as verified retirement or log a whole export, which may include installation locations/custom arguments. [D4], [S14], [S23]

## Native alternatives without a new runtime/module

### COM/WinRT: real API, but not a proven drop-in PS5.1 recipe

- App Installer's package payload includes `Microsoft.Management.Deployment.winmd`. The official COM design uses out-of-process COM activation, not ordinary WinRT construction. Microsoft's module implements CLSID activation and a separate elevated activation path. These establish an existing native API, not an automatic late-bound `New-Object -ComObject` solution. [S15], [S16], [S29]
- `PackageCatalog.FindPackages` is stronger than CLI `list`: it converts a search-result failure into an error result instead of silently accepting remaining matches. A prospective adapter must require successful `Connect`, successful `FindPackages`, no truncation, verified catalog identity, and inspected installed identity/scope. However, `Connect` does not independently certify a fresh source update; local ARP enumeration can also skip unreadable/malformed entries. “Typed” must not be confused with “complete under every inventory failure.” [S6], [S17], [S24]
- A blanket “PS5.1 cannot use WinGet” claim is too broad. Microsoft's module targets `net48` as well as modern .NET and declares PowerShell 5.1; the inspected explicit Windows PowerShell rejection is conditional on **in-process** use, which the inspected utility selects for **SYSTEM** execution. Nevertheless, the module is optional and not provisioned here, and a custom PS5.1 WinMD/COM bridge still requires Windows validation of activation, metadata loading, scope, errors, and supported versions. Do not add it as an untested guaranteed prerequisite. [S18], [S25], [S26], [S27]

### Narrow portable native-record inventory: recommended avenue after identity clarification

For a **confirmed portable-only managed identity**, a small read-only PS5.1 registry probe is a more bounded candidate than a general WinGet wrapper:

- WinGet constructs its portable product code from `<package-id>_<source-identifier>` and stores `WinGetPackageIdentifier`, `WinGetSourceIdentifier`, and `WinGetInstallerType` in its ARP registration. It writes its own uninstall string as `winget uninstall --product-code <product-code>`. [S19], [S28]
- PS5.1's .NET Framework already supplies read-only `RegistryKey.OpenBaseKey`/`OpenSubKey` with explicit registry views. Distinguish genuinely missing keys from access errors; do not instantiate WinGet's `PortableARPEntry` class for inventory, because its constructor creates a missing entry. [D5], [D6], [S20]
- Proposed contract: inspect only the bounded native locations/views used for the approved portable product code(s), in current-account and machine scope; validate exact ID/source/type and metadata types; treat malformed, unreadable, conflicting, or unexpected relevant records as failure. A fully readable absent set establishes **absence of those native registrations**, without requiring source correlation or the optional module. Do not enumerate other users or scan HOME.
- For one verified registration, invoke native `winget uninstall --product-code <verified-code> --exact --source winget --scope <verified-scope> --silent --preserve --accept-source-agreements --disable-interactivity`, after the source-configuration check. Require exit `0`, then repeat the same native-record inventory and require the authorized registration to be absent. Any nonzero uninstall result remains failure even if a later probe is empty. Let WinGet perform removal; never use the stored command as executable input.
- This is **conditional design advice**, not a completed contract for arbitrary historical MSI/EXE installations. It requires evidence that the approved historical package IDs/installer types map to these records, and native Windows fixtures. Unknown/manual installations remain preserved with manual-cleanup warnings when detected.

## Specific remaining design choice

**First settle the recognized Windows identity set, then choose bounded native inventory rather than weakening absence verification.**

Microsoft's inspected manifests at commit `7978bfa04f46a9f4520ceddf0f8957f297ac3db3` show `infisical.infisical` versions `0.39.1` and `0.43.134`, both ZIP/portable, x64/ARM64. The official API returned no history for the exact `manifests/i/Infisical/CLI` path. This does **not** prove that no historical alias/path ever existed, but the setup command's literal `Infisical.CLI` is not evidence of a successful official installation. [M1], [M2], [M3]

The maintainer must decide whether retirement remains limited to the original literal identity (preserving other IDs), or explicitly recognizes the evidenced `infisical.infisical` portable identity as well. Do not infer that authorization from this report. For the selected identities, establish historical installer coverage and use the narrow native-record contract if portable-only; otherwise validate a PS5.1 native COM bridge with explicit native identity checks. Until that is evidenced, Windows remains incomplete **for a specific identity/inventory reason**, not because every machine must install PS7 or because all unknown manual applications must be inventoried.

## Required implementation fixtures / native validation

No fixtures or Windows operations were run for this research. The later implementation should cover:

1. Module absent but complete native managed-record inventory empty: verified no-op; custom PATH binary preserved/warned, not removal authority.
2. Exact managed native record: one targeted uninstall, independent postcheck, second run no-op; preserve custom files/credentials/unrelated registrations.
3. Query source-search failure with exit `0` **and** `0x8A150014`: neither treated as complete inventory; signed/unsigned HRESULT representations tested.
4. Source missing/substituted/malformed; agreements refused; offline stale source; update failure; source unavailable while installed native record remains.
5. Multiple matches/versions, portable versus MSI/EXE, both scopes/views, access denial and malformed native records: no guessed narrowing or broad removal.
6. Uninstall nonzero, timeout, unsupported flags, elevated user-scope restriction, modified portable payload, lingering registration, and unreadable postcheck: fail retained through unrelated work/log finalization.
7. Purge preference enabled: explicit `--preserve`; no `--force`, `--purge`, source reset, replacement package, or raw registry-command execution.
8. If COM chosen: stock Windows PS5.1 with only App Installer; metadata/activation and elevated/non-elevated behavior; source search failures/truncation; no module/runtime installation. Linux PowerShell mocks cannot establish these behaviors.

**Execution boundary:** only public first-party documentation/source downloads and read-only repository inspection were used. No live WinGet, setup, install/uninstall, permission, daemon, remote-host, or process-environment inventory action occurred. The only repository edit is this findings file.

## First-party sources

Inline citations link to Microsoft documentation, pinned Microsoft source, and official package manifests; the API history lookup is explicitly identified as a non-exhaustive observation.

[D1]: https://learn.microsoft.com/en-us/windows/package-manager/winget/list
[D2]: https://learn.microsoft.com/en-us/windows/package-manager/winget/uninstall
[D3]: https://learn.microsoft.com/en-us/windows/package-manager/winget/source
[D4]: https://learn.microsoft.com/en-us/windows/package-manager/winget/export
[D5]: https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registrykey.opensubkey?view=netframework-4.8.1
[S1]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Commands/ListCommand.cpp#L91-L102
[S2]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Commands/UninstallCommand.cpp#L99-L138
[S3]: https://github.com/microsoft/winget-cli/blob/95add984d147223256630f762824f768d98d9485/src/AppInstallerCLICore/Commands/ListCommand.cpp#L84-L95
[S4]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/doc/windows/package-manager/winget/returnCodes.md#L20-L90
[S5]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Workflows/WorkflowBase.cpp#L1007-L1051
[S6]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerRepositoryCore/Microsoft/ARPHelper.cpp#L383-L556
[S7]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerRepositoryCore/CompositeSource.cpp#L1136-L1160
[S8]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Workflows/WorkflowBase.cpp#L184-L279
[S9]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Workflows/SourceFlow.cpp#L231-L262
[S10]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Workflows/SourceFlow.cpp#L390-L420
[S11]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/ExecutionReporter.cpp#L103-L137
[S12]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Workflows/UninstallFlow.cpp#L86-L350
[S13]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Workflows/PortableFlow.cpp#L316-L348
[S14]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Workflows/ImportExportFlow.cpp#L94-L177
[S15]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLIPackage/AppInstallerCLIPackage.wapproj#L227-L251
[S16]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/PowerShell/Microsoft.WinGet.Client.Engine/Helpers/ManagementDeploymentFactory.cs#L24-L236
[S17]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/Microsoft.Management.Deployment/PackageCatalog.cpp#L124-L174
[S18]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/PowerShell/Microsoft.WinGet.Client.Engine/Commands/Common/ManagementDeploymentCommand.cs#L29-L40
[S19]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/PortableInstaller.cpp#L478-L506
[S20]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCommonCore/PortableARPEntry.cpp#L15-L73
[M1]: https://github.com/microsoft/winget-pkgs/blob/7978bfa04f46a9f4520ceddf0f8957f297ac3db3/manifests/i/infisical/infisical/0.39.1/infisical.infisical.installer.yaml
[M2]: https://github.com/microsoft/winget-pkgs/blob/7978bfa04f46a9f4520ceddf0f8957f297ac3db3/manifests/i/infisical/infisical/0.43.134/infisical.infisical.installer.yaml
[M3]: https://api.github.com/repos/microsoft/winget-pkgs/commits?path=manifests/i/Infisical/CLI&per_page=1
[D6]: https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registrykey.openbasekey?view=netframework-4.8.1
[S21]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerRepositoryCore/CompositeSource.cpp#L1477-L1736
[S22]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerRepositoryCore/RepositorySource.cpp#L796-L904
[S23]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Commands/ExportCommand.cpp#L55-L69
[S24]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/Microsoft.Management.Deployment/PackageCatalogReference.cpp#L125-L238
[S25]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/PowerShell/Microsoft.WinGet.Client.Engine/Microsoft.WinGet.Client.Engine.csproj#L5-L20
[S26]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/PowerShell/Microsoft.WinGet.Client/ModuleFiles/Microsoft.WinGet.Client.psd1#L35-L44
[S27]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/PowerShell/Microsoft.WinGet.Client.Engine/Common/Utilities.cs#L37-L60
[S28]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Workflows/PortableFlow.cpp#L25-L41
[S29]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/doc/specs/%23888%20-%20Com%20Api.md#L24-L45
[S30]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Workflows/WorkflowBase.cpp#L1313-L1425
[S31]: https://github.com/microsoft/winget-cli/blob/000f6b55151cb0f1afd2933bb54c62a4724b9ca8/src/AppInstallerCLICore/Workflows/WorkflowBase.cpp#L1124-L1280
