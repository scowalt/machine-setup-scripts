# BB 0.45.0 native plugin-refresh contract comparison

**Date:** 2026-10-09

**Status:** source review complete; subsequent owner-approved implementation delegates plugin refresh to the native CLI

## Conclusion

**No breaking change was found in the native contract consumed by setup.** The exact published 0.45.0 source retains the seven routes, request/result shapes, source/pin intent, effective disabled state, safe-mode refusal, rollback classification and packaged local-server identity chain reviewed for 0.44.0. In particular, `createPluginUpdates` is byte-identical, not merely similar. [[S1](#s1), `package/server/dist/start-server.js:198735-199248`; [S2](#s2), `package/server/dist/start-server.js:204156-204669`; detailed paired citations below]

However, surrounding implementation is not identical: 0.45.0 preserves a new internal `enabledFollowsDefault` flag, advances the plugin SDK, removes the legacy Jiti loader and adds Host-header validation. These differences matter for hidden intent, candidate eligibility and real activation; see the dedicated sections below.

The initial recommendation was narrow 0.45.0 support: at research-start commit [`7f274a4`](https://github.com/scowalt/machine-setup-scripts/blob/7f274a4/lib/bb-plugin-refresh.py#L411), setup accepted only 0.44.0. The owner subsequently chose **native CLI delegation instead of a release allowlist or custom plugin-result verifier**, to reduce code and avoid recurring compatibility-gate failures. See [the implementation disposition](#owner-approved-simplification-and-validation) below.

The comparison itself involved no native request, plugin migration, activation, rollback or continuity test. It does not establish live plugin/workflow readiness or prove future releases have identical internals.

## Sources and provenance

### S1

| Key | Versioned primary artifact | Provenance |
| --- | --- | --- |
| **S1** | `bb-app@0.44.0`: [official registry metadata](https://registry.npmjs.org/bb-app/0.44.0), [official tarball](https://registry.npmjs.org/bb-app/-/bb-app-0.44.0.tgz) | Registry integrity `sha512-++yBrXnvHyfTasH3gFa/SUmOANoUq58RNyxTcgkVYgolEES1JqzHByCnvCgEqmb9eThwveFeihXm58Ut5bJ0Zg==`; tarball SHA-256 `5b657e2a4209702c9bf793c21b2ceee83d158a176ee80381f8df1e42845792a2`; source `gitHead` SHA-1 `0baa605b32a00619c1d7e3f32be6553ebcf8244a`. Package identity is `bb-app` 0.44.0. [[S1](#s1), `package/package.json:1-3`] |
| Files | Reviewed-file correspondence | Downloaded `package/server/dist/start-server.js` SHA-256 `344b576226854db7d54ecb4e397c3b904d0776936bb63743a28a05a67beeb008` and launcher `package/dist/bb-app.js` SHA-256 `2eb3c34b952fe24769458e292c2670bafc882653ef8673587faebfc6f3cb5c4e` match the hashes recorded by the prior 0.44.0 review. This is equality of identified files, not execution evidence. |

### S2

| Key | Versioned primary artifact | Provenance |
| --- | --- | --- |
| **S2** | `bb-app@0.45.0`: [official registry metadata](https://registry.npmjs.org/bb-app/0.45.0), [official tarball](https://registry.npmjs.org/bb-app/-/bb-app-0.45.0.tgz) | Registry integrity `sha512-UaE+P7I5I8RcMNNCwBRmsflWKiYjJ7j/RcWG3L09sWXgUTOQjF9SB9jQu4UcGZNEIKL5h/S4vYUWWdNSP8gBzA==`; tarball SHA-256 `3692ae47f70f747c06f2ae2659b613ec96b4e14c5e479560eff380f4c90a11e7`; source `gitHead` SHA-1 `129f621771a3e275773992db648316966ac207cf`. Package identity is `bb-app` 0.45.0. [[S2](#s2), `package/package.json:1-3`] |
| Files | Reviewed-file identities | `package/server/dist/start-server.js` SHA-256 `7f8291715d4efb854b2f01313f01120c089e32afe979eb6590e610361afacffc`; `package/dist/bb-app.js` `c7e4090ceba9bff8b574cb6c0c05d49552a5df040a51022e3129d66424473c51`; `package/dist/bb-server.js` `27c0ee56f88b6bd589af1a03d3e7b55b2966cb3d7e177b262c4031f38951ba34`; `package/server/dist/index.js` `f37884b4476ff4ee7d3a95cf8b45e93db82c70e14a4cac615a53ec36cad94083`. |

Both tarballs were downloaded directly from the official registry and checked against `dist.integrity` (SHA-512) **and** `dist.shasum` (tarball SHA-1): S1 `d5c73cdfe0bd0025633f014a5b6793dc8de031d0`; S2 `ecbe36d8f287e77b43708002de0d5282e5ec82d7`. `gitHead` is a separate source-commit identifier, not tarball integrity. The 0.45.0 installed `server/dist/start-server.js` also matches the S2 hash above; that is read-only file correspondence, not a running-process attestation.

Artifacts, registry captures, numbered excerpts and static function comparisons are retained privately at `/tmp/bb-native-contract-source-stoscqbl/`. File/line citations below refer to LF-delimited **published tarball contents**, with `package/` as the archive root, unless identified as GitHub sources. Thus the claims can be reproduced from the versioned tarball links even if the temporary captures disappear. The earlier [0.44.0 review](2026-10-01-bb-plugin-refresh-api.md) establishes historical approval; primary source is rechecked here rather than treating that note as proof of 0.45.0 behavior.

A standalone background agent analyzed numbered source excerpts after its read-only shell sandbox refused startup; no sandbox bypass was used. The parent independently checked source diffs, local identity, additional runtime changes and citations. Only source/metadata retrieval and static text/hash processing were used; no BB executable/module, live configuration, service inventory, setup entry point or plugin endpoint was executed or queried.

## Contract comparison

### Routes and shapes

The paired source excerpts register the same relative native routes:

| Operation | 0.44.0 and 0.45.0 contract |
| --- | --- |
| Inventory | `GET /plugins` returns `{plugins: plugins.list()}`. Each item exposes `id`, `source`, `version`, `provenance`, `updateState`, `enabled`, runtime `status`, services and schedules. [[S1](#s1), `package/server/dist/start-server.js:37841-37895,182550-182562`; [S2](#s2), `package/server/dist/start-server.js:42225-42279,191613-191625`] |
| Source detail | `GET /plugins/:id/source` returns the native source view or 404. The schema contains requested/resolved source plus optional subdirectory, range, tag prefix, resolved tag, integrity and registry. [[S1](#s1), `package/server/dist/start-server.js:37775-37794,182796-182802`; [S2](#s2), `package/server/dist/start-server.js:42159-42178,191859-191865`] |
| Update check | `POST /plugins/updates/check` accepts a strict object with optional nonempty `id`; success is `{results}` and service errors return 422. Entry outcomes remain `current`, `update-available`, `pinned`, `incompatible`, or `unavailable`, with installed resolution and optional candidate/blocked/detail fields. [[S1](#s1), `package/server/dist/start-server.js:37743-37766,182721-182735`; [S2](#s2), `package/server/dist/start-server.js:42127-42150,191784-191798`] |
| Apply update | `POST /plugins/:id/update` requires the empty JSON object `{}`. Success returns `{applied, from, to?, outcome, detail?}`, where outcome is `current`, `updated`, or `rolled-back`; refusal/error returns 422. [[S1](#s1), `package/server/dist/start-server.js:37767-37774,182747-182763`; [S2](#s2), `package/server/dist/start-server.js:42151-42158,191810-191826`] |
| Safe mode | `GET /plugins/safe-mode` returns `{enabled:boolean}`; a separate `PUT` changes it. The refresh operation need only read the former and must not call the latter. [[S1](#s1), `package/server/dist/start-server.js:37963-37969,182809-182823`; [S2](#s2), `package/server/dist/start-server.js:42347-42353,191872-191886`] |

These handlers are mounted beneath `/api/v1` in both releases, so the complete plugin paths are `/api/v1/plugins`, `/api/v1/plugins/:id/source`, `/api/v1/plugins/safe-mode`, `/api/v1/plugins/updates/check` and `/api/v1/plugins/:id/update`. The separate system route is `/api/v1/system/config`; `/health` remains at the root. [[S1](#s1), `package/server/dist/start-server.js:44819-44825,210250-210259,210532-210538`; [S2](#s2), `package/server/dist/start-server.js:49202-49208,215815-215824,216138-216144`]

The reviewed schema block (S1 lines 37727–37971; S2 lines 42111–42355) is byte-identical. The whole plugin-route function is not: 0.45.0 adds caller-token validation to **plugin RPC invocation**, outside the refresh routes above. Do not confuse that new `x-bb-plugin-caller` requirement with a requirement for core update checks or updates. [[S1](#s1), `package/server/dist/start-server.js:182956-183016`; [S2](#s2), `package/server/dist/start-server.js:191190,192019-192092`]

### Source, range, pin, local and builtin preservation

Both versions parse the same source families: `builtin:`, `git:`, `npm:`, HTTP(S) Git, and local paths. Npm intent distinguishes default, exact, range and tag; Git intent distinguishes refs and semver ranges with optional tag prefixes. [[S1](#s1), `package/server/dist/start-server.js:187127-187169,187171-187294`; [S2](#s2), `package/server/dist/start-server.js:196260-196304,196306-196437`]

Both resolvers preserve the following behavior:

- Path and builtin sources are reported as pinned and are not selected for managed updates. [[S1](#s1), `package/server/dist/start-server.js:198871-198880`; [S2](#s2), `package/server/dist/start-server.js:204292-204301`]
- Exact npm versions are pinned. Npm tags and ranges select only versions allowed by the existing intent, filter prereleases unless the intent permits them, and apply BB/plugin-SDK compatibility checks. [[S1](#s1), `package/server/dist/start-server.js:189605-189677,189682-189799`; [S2](#s2), `package/server/dist/start-server.js:199024-199096,199101-199218`]
- Git commit refs are pinned; recorded tags remain pinned unless a moved-tag security check makes the source unavailable; branches can advance; semver Git ranges retain the recorded range/tag prefix and search compatible matching release tags. [[S1](#s1), `package/server/dist/start-server.js:189901-190034`; [S2](#s2), `package/server/dist/start-server.js:199320-199453`]
- The source-detail response is derived from the installed row and preserves requested source, Git subdirectory/range/tag prefix/resolved tag, npm integrity and registry. [[S1](#s1), `package/server/dist/start-server.js:199084-199107`; [S2](#s2), `package/server/dist/start-server.js:204505-204528`]

Activation retains provenance and source intent while advancing only the selected exact resolution. Git staging passes the existing `row.source`, URL, subdirectory and selector; npm activation reconstructs its native source string from the retained package/registry/requested-spec intent. This is semantic preservation, not a promise that arbitrary legacy source-string formatting is byte-preserved. [[S1](#s1), `package/server/dist/start-server.js:188897-188907,190099-190101,190887-190920,191080-191108`; [S2](#s2), `package/server/dist/start-server.js:198315-198327,199518-199520,200306-200339,200499-200527`]

Unavailable sources remain distinct from pins: a retired remote-marketplace npm source returns `unavailable`, and ambiguous legacy tag/branch evidence can also refuse resolution rather than silently tracking a branch. Candidate selection is repeated before npm activation; a changed candidate is an error. [[S1](#s1), `package/server/dist/start-server.js:198822-198860,198881-198886,199158-199172`; [S2](#s2), `package/server/dist/start-server.js:204243-204281,204302-204307,204579-204593`] None of these source-inferred guarantees was exercised against real 0.45.0 plugins.

### Disabled state

In 0.44.0, activation writes `enabled: args.row.enabled`, and `loadOne` identifies but does not start a row whose `enabled` value is false. [[S1](#s1), `package/server/dist/start-server.js:188897-188912,197646-197668`]

The same behavior remains in 0.45.0. In addition, the installed row now has `enabledFollowsDefault`, defaulting to false, and activation explicitly carries both `enabled` and `enabledFollowsDefault` into the replacement registration. [[S2](#s2), `package/server/dist/start-server.js:197883-197925,198315-198331,203075-203097`]

Native 0.45.0 also includes `enabledFollowsDefault` in its pre-activation registration equality check, database upsert and rollback restoration. Explicit enable/disable clears default-following intent. Builtin registration can follow bundled defaults when that flag is true, but managed update activation explicitly carries the prior flag and effective `enabled` value. [[S2](#s2), `package/server/dist/start-server.js:32518-32548,32567-32570,203670-203672,203956-203974,204026-204056`]

The public installed-plugin schema **and actual `list()` projection** expose only `enabled`, not `enabledFollowsDefault`. An external before/after inventory comparison can verify effective disabled status but cannot directly verify this new hidden intent. This is a verification limitation, not evidence of lost state. [[S2](#s2), `package/server/dist/start-server.js:42225-42278,205103-205201`]

### Safe mode

Both versions consult `safeModeActivationRefusal` before resolving or applying an update and return an unsuccessful native outcome when activation is forbidden. [[S1](#s1), `package/server/dist/start-server.js:199109-199145`; [S2](#s2), `package/server/dist/start-server.js:204530-204566`] Native safe mode exempts builtin/included-builtin sources; loaders suppress affected enabled rows and do not activate disabled rows. [[S1](#s1), `package/server/dist/start-server.js:197631-197668`; [S2](#s2), `package/server/dist/start-server.js:203060-203097`]

Setup reads safe mode before invoking the CLI and defers the whole refresh without changing the mode. Subsequent CLI failures, including a mode change during execution, follow native exit semantics rather than a custom HTTP-error classifier; earlier failures remain failed. [`safe_mode` and `refresh`](../../lib/bb-plugin-refresh.py#L559) own that boundary. No 0.45.0 safe-mode request was executed during research or validation.

### State, settings, secrets, schedules and rollback

The 0.44.0 and 0.45.0 snapshot flows are structurally the same. Before changing the active registration, native activation creates an on-disk snapshot containing:

- the plugin `data.db`, after a WAL checkpoint;
- the plugin secrets directory;
- host key/value state, settings and schedules;
- the complete prior plugin registration. [[S1](#s1), `package/server/dist/start-server.js:188444-188465,188525-188599`; [S2](#s2), `package/server/dist/start-server.js:197861-197882,197943-198017`]

Restore removes current database sidecars, restores or removes the database as appropriate, replaces the secrets directory, restores host state, and later restores the prior registration. [[S1](#s1), `package/server/dist/start-server.js:188601-188674`; [S2](#s2), `package/server/dist/start-server.js:198019-198092`]

If replacement activation enters an error state during the stabilization window, both versions mark rollback pending, restore snapshot state and registration, reload the prior plugin, record the failed candidate, and report a `PluginActivationRolledBackError`. [[S1](#s1), `package/server/dist/start-server.js:188797-188845,188859-188978`; [S2](#s2), `package/server/dist/start-server.js:198215-198263,198277-198397`] The update service converts that condition into a successful HTTP result carrying `applied:false` and `outcome:"rolled-back"` rather than a transport failure. [[S1](#s1), `package/server/dist/start-server.js:199207-199218`; [S2](#s2), `package/server/dist/start-server.js:204628-204639`]

Consequently, HTTP 200 or command success alone cannot prove every plugin updated successfully. The original setup verifier classified `rolled-back` as incomplete and checked final state; the later owner-approved simplification accepts BB's CLI exit semantics instead and reports **command completion**, not verified plugin readiness. Snapshot presence still does not prove arbitrary migrations or external side effects are reversible.

## Local identity

### Native packaged main-server chain

The published package name and `bb-server` bin declaration remain `bb-app` and `dist/bb-server.js`; both ship `server/dist`. The 0.45.0 manifest adds `win32` and `host-daemon/dist/bb.cmd`, but that does not authorize extending setup's Linux/macOS identity proof to Windows. [[S1](#s1), `package/package.json:1-3,35-56`; [S2](#s2), `package/package.json:1-3,35-58`]

The following paired functions were checked directly and are **byte-identical**, including their environment handling:

| Identity link | 0.44.0 | 0.45.0 |
| --- | --- | --- |
| Package-root resolution selects `server/dist/index.js` for packaged runs; source checkouts use the workspace entry instead. | S1 `dist/bb-app.js:14065-14102` | S2 `dist/bb-app.js:18491-18528` |
| Native local runtime state resolves managed configuration and removes remote `BB_SERVER_URL` selection in local mode. | S1 `dist/bb-app.js:14103-14175` | S2 `dist/bb-app.js:18529-18601` |
| Main-server environment supplies account runtime `BB_DATA_DIR`, `BB_SERVER_PORT` and package version. | S1 `dist/bb-app.js:15065-15077` | S2 `dist/bb-app.js:19490-19502` |
| Full-stack launcher spawns `process.execPath` with exactly `[serverEntry]`, adds a fresh UUID `BB_SERVER_LAUNCH_ID`, and waits for that identity. | S1 `dist/bb-app.js:15346-15379` | S2 `dist/bb-app.js:19821-19854` |
| Health wait requires the expected launch ID, not merely a responsive port. | S1 `dist/bb-app.js:14912-14941` | S2 `dist/bb-app.js:19333-19362` |
| Standalone `bb-server` also selects local runtime state and spawns exactly `[serverEntry]`, with resolved data/port environment. It does not create the full-stack launch UUID. | S1 `dist/bb-server.js:12383-12395,12415-12464` | S2 `dist/bb-server.js:16761-16773,16793-16842` |
| Server configuration loads data/port and carries an optional launch ID from environment. | S1 `server/dist/index.js:9491-9507,9608-9622,9647-9767` | S2 `server/dist/index.js:13417-13433,13534-13548,13573-13693` |

Each S1/S2 cell cites the corresponding [official artifact](#sources-and-provenance), relative to `package/`. `spawnLoggedProcess` is also byte-identical (S1 `dist/bb-app.js:2116-2132`; S2 `dist/bb-app.js:2619-2635`). These are bounded function comparisons, not claims that all transitive dependencies or executable bundles are identical.

The server maps `BB_SERVER_LAUNCH_ID` to its runtime config and echoes it on root `/health`, with `ok:true` and optional server-move state. `/api/v1/system/config` still returns the actual native `dataDir`. [[S1](#s1), `package/server/dist/start-server.js:177674-177712,210250-210259,216339-216341`; [S2](#s2), `package/server/dist/start-server.js:182913-182950,215815-215824,222248-222250`]

This keeps the evidence fields needed by setup's existing proof: account UID and PID/start identity, packaged main entry, safe package/data files and snapshots, accepted server-side socket ownership, optional matching launch ID and matching data directory. Health/config responses alone are not ownership attestations; an enrolled daemon, inherited remote URL or loopback tunnel is still insufficient. [`Processes`, `discover` and `NativeApi`](../../lib/bb-plugin-refresh.py) own those additional checks before CLI handoff; setup does not independently inspect the CLI's subsequent HTTP connections or plugin outcomes. Source compatibility does not establish that a particular live process satisfies them, and no process or socket inventory was performed here.

### Desktop source correspondence

At the npm metadata's exact source commits, the four desktop files below are byte-identical between [D44 `0baa605…`](https://github.com/get-bb/bb/tree/0baa605b32a00619c1d7e3f32be6553ebcf8244a/apps/desktop) and [D45 `129f621…`](https://github.com/get-bb/bb/tree/129f621771a3e275773992db648316966ac207cf/apps/desktop):

- [`src/bb-app-bridge.ts:1`](https://github.com/get-bb/bb/blob/129f621771a3e275773992db648316966ac207cf/apps/desktop/src/bb-app-bridge.ts#L1) imports `bb-app/dist/bb-app.js`.
- [`src/app-paths.ts:24-51`](https://github.com/get-bb/bb/blob/129f621771a3e275773992db648316966ac207cf/apps/desktop/src/app-paths.ts#L24-L51) resolves the unpacked bridge and native package subtree.
- [`src/owned-runtime-supervisor.ts:14-19,137-157`](https://github.com/get-bb/bb/blob/129f621771a3e275773992db648316966ac207cf/apps/desktop/src/owned-runtime-supervisor.ts#L137-L157) records the bridge process, not a main-server ownership attestation.
- [`src/server-probe.ts:9-15,166-231`](https://github.com/get-bb/bb/blob/129f621771a3e275773992db648316966ac207cf/apps/desktop/src/server-probe.ts#L166-L231) uses health/config compatibility probes, not account/accepted-socket ownership proof.

Both [D44 packaging](https://github.com/get-bb/bb/blob/0baa605b32a00619c1d7e3f32be6553ebcf8244a/apps/desktop/electron-builder.config.json#L6-L21) and [D45 packaging](https://github.com/get-bb/bb/blob/129f621771a3e275773992db648316966ac207cf/apps/desktop/electron-builder.config.json#L6-L21) unpack `dist/bb-app-bridge.mjs` and `node_modules/**`. A bridge PID or desktop connection selection therefore still cannot replace verification of the actual packaged main process. This is repository-source correspondence at the published package commits, not inspection of a signed desktop release or proof that its embedded npm bytes match S2.

## Other material changes

- **Plugin SDK:** the bundled SDK changes from `0.5.29` to `0.6.15`. Compatibility resolution still evaluates both BB and SDK requirements, so identical resolver logic need not select the same candidates. [[S1](#s1), `package/server/dist/start-server.js:16205,189516-189530,189682-189724`; [S2](#s2), `package/server/dist/start-server.js:20196,198935-198949,199101-199143`]
- **Loader:** 0.45.0 removes `legacyJitiPluginLoader` branches. Source/unsupported prebuilt entries now follow native build/ESM/CommonJS paths; CommonJS cleanup resolves the actual filename before removing its cache entry. This can change real activation outcomes even though update response shapes and rollback classification are retained. [[S1](#s1), `package/server/dist/start-server.js:197313-197408,197866-197925`; [S2](#s2), `package/server/dist/start-server.js:202757-202837,203296-203339`]
- **HTTP Host/origin guard:** 0.45.0 adds a global `requestHostProblem` gate and tightens host/origin parsing. Its trusted-host test explicitly accepts IP addresses, including setup's direct `127.0.0.1` connection, and requests without `Origin` are accepted by the unchanged `browserRequestProblem`. Thus no new caller token or configured public hostname is required for this loopback path, as inferred from source—not tested by a request. [[S1](#s1), `package/server/dist/start-server.js:170221-170290,210211-210230`; [S2](#s2), `package/server/dist/start-server.js:175062-175152,215770-215780`; [`NativeApi.request`](../../lib/bb-plugin-refresh.py#L485)]
- **Other scope changes:** Windows-drive handling for local Git sources and a manifest-derived provider catalog are new. They do not change the reviewed update route/result shapes, and native Windows setup policy remains a separate boundary. [[S2](#s2), `package/server/dist/start-server.js:196272-196394,196909-196932`]

## Owner-approved simplification and validation

The owner rejected maintaining a release-by-release plugin compatibility framework and authorized a thin native operation:

```bash
bb plugin update --all --yes
```

The 0.45.0 CLI itself checks compatible updates, skips native pinned/incompatible/unavailable selections and applies selected updates. It can print a rolled-back result without exiting nonzero; an actual SDK/apply exception exits unsuccessfully. Accepting those native exit semantics is an explicit trade-off, not a claim that zero means all plugins updated. [[S2](#s2), `package/host-daemon/dist/bb-chunks/plugin-MFPSJT7X.js:2596-2598`]

Implementation in [`lib/bb-plugin-refresh.py`](../../lib/bb-plugin-refresh.py) removes the release allowlist, per-plugin inventory/source/update API calls, result classifier and post-update verification. Existing discovery, account/package/data/process/peer preflight, stable snapshots, readiness and stopped/safe-mode deferrals remain. After preflight, it executes that server's bundled CLI with its Node, explicit loopback URL/data directory, disabled CLI re-exec and a minimal environment; native output is suppressed rather than exposing arbitrary diagnostics/secrets. Nonzero exit, timeout and preflight errors still fail setup through normal finalization. Source selection, pins, disabled/default-following state and rollback remain BB's responsibility, with no new adapters, database inspection or runtime hash pinning.

The native CLI's explicit `BB_SERVER_URL` takes precedence over configured defaults, and `BB_CLI_REEXEC=1` prevents inherited-command redirection. [[S2](#s2), `package/host-daemon/dist/bb:3-4`, `package/host-daemon/dist/bb-chunks/chunk-OPUQY62Y.js:3`] Targeted fixtures additionally assert that inherited CLI/remote/proxy/Node controls never reach the child.

BB installation/update remains unchanged, including the existing stable npm/server lifecycle. The separate `bb updates app apply --yes` requires an update-enabled launcher; setup's current `start --bundled` service does not opt in. The simplification therefore changes plugin refresh, not app lifecycle or the managed installation location. [[S2](#s2), `package/README.md:121-129`, `package/host-daemon/dist/bb-chunks/updates-GLTSTEHJ.js:2`; [`bb_write_bb_guard`](../../ubuntu.sh)]

The canonical policy/wrapper was regenerated into all five Bash entry points; their versions incremented to macOS 295, Ubuntu 328, Pi 269, Bazzite 173 and WSL 252. Native Windows remains unchanged. The [approved plan](../plans/2026-10-01-bb-plugin-refresh.md) and agent guidance now describe native delegation rather than the superseded allowlist/result verifier.

Contained validation passed **15/15 affected entries**, including all **73 plugin-refresh tests**. Artifacts: `/tmp/setup-fixture-matrix-rjzn4o8y`, with mandatory kernel/FD self-test, private stdio/roots and sequential suites. The cohort covered containment/extraction, setup-default, BB refresh/desktop/preparation/server, reliability, headless, shared runtime, CLT, Homebrew results, reboot, weekly, Paseo non-management and AI-agent wiring. Existing native Node/PowerShell plus individually selected mise/Chezmoi/Bun executables were used; optional dotfiles/installed-code integrations remained disabled. Five unittest skips remain explicit; available Linux PowerShell fixtures do not establish native Windows behavior.

The runner used sanitized `env -i PATH=/usr/bin:/bin`, `/usr/bin/python3 -I tests/run-fixture-matrix.py`, Node `/home/scowalt/.local/share/mise/installs/node/24.20.0/bin/node`, PowerShell `/opt/microsoft/powershell/7/pwsh`, tool PATH `/usr/bin:/bin:/tmp/bb-cli-delegation-tools.Jub8HEs9` and a 300-second per-suite limit. `results.json` retains the exact ordered cohort. The earlier 3/3 pilot is retained at `/tmp/setup-fixture-matrix-senmqwq6`.

Registry integrity, primary-source citations and paired functions/schemas were checked statically. Bash syntax, ShellCheck, Python AST parsing, embedding consistency and `git diff --check` pass. Behavioral fixtures mock CLI/HTTP/process effects before executing helpers/callers; they execute neither installed BB nor plugins. No live setup, service action, BB/plugin request, application execution or rollout was performed. Native platform, migration, rollback and required-workflow usability remain separately authorized evidence; the original containment incident's uncertainty is unchanged.

## Publication validation

Before publishing, the exact contained pre-push dispatcher passed **46/46 entries** at `/tmp/setup-fixture-matrix-6nvyp8qz`, using the same existing native tools above and 900-second suite deadlines. This includes every `tests/*.sh` contract plus the five direct containment/hook/CLT/Homebrew/managed-skill suites; optional integrations retain their skips. The two new source comments were removed to comply with the repository's comment-free policy before this run.

Native ShellCheck, Bash/Python syntax, embedding consistency, staged whitespace and redacted Gitleaks checks passed. The pinned cached Python 3.14 parser dependencies checked the complete index with zero comment-policy violations, and all 13 policy adapter/index tests passed under kernel containment. Cached Markdownlint checked the root Markdown and changed research/plan documents without downloading tools; two empty table cells needed compact-format repair. Private static logs are retained at `/tmp/bb-cli-publication-static-_1yvtulh` and the subsequent passing run.

Publication uses command-local `LEFTHOOK=0` because the wrappers resolve tools via `bunx`/`uv`; their validation is performed directly with existing tools and mandatory contained contracts rather than uncontained tool resolution. No hook configuration is changed, and publication authorizes no live setup or BB/plugin action.
