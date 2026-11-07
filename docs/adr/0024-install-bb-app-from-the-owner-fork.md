# Install bb-app from the owner fork

The Ubuntu bb server and BB machine preparation install `bb-app` from the owner fork's latest release, `https://github.com/scowalt/bb/releases/download/bb-app-latest/bb-app.tgz`, instead of `bb-app@latest` from npm. The owner maintains [`scowalt/bb`](https://github.com/scowalt/bb) with changes upstream does not ship, such as ranking agent work ahead of bb for the Linux out-of-memory killer, and wants every machine to run it. This extends [ADR 0023](0023-install-owner-desktop-forks-on-headed-macs.md) from the desktop app to the server package, and keeps [ADR 0022](0022-delegate-bb-trust-to-native-tools.md)'s trust model: npm installs the archive with the same script allowlist and no setup-side checksum or signature gate.

The fork publishes `bb-app` from its `Fork Release` workflow on every push to `main`: a versioned `bb-app-v<version>` release and the moving `bb-app-latest` release with `bb-app.tgz` and a `bb-app-version.json` feed. Fork builds name the fork as their release repository, so a server's own update check reads that feed and its in-app updater installs the fork's versioned tarball rather than `bb-app@<version>` from npm. Enrolled machines install and update from their server's package as before, so they follow the server.

Fork versions are `<next upstream patch>-fork.<run number>`, which the stable-version checks rejected as a prerelease. Setup's package checks now accept exactly `X.Y.Z` and `X.Y.Z-fork.N`; other prereleases such as release candidates and nightlies are still refused.

npm 12 defaults `allow-remote` to `none`, which refuses any package named by URL, including this archive. The install passes `--allow-remote=root`, which permits only the archive named on the command line; URL dependencies anywhere in its tree are still refused. npm 11 defaults to `all` and accepts the flag unchanged.

## Considered options

- Keep npm. Servers then run upstream's package, and bb's updater replaces any hand-installed fork with upstream's next release.
- Run each server from a source checkout of the fork. bb updates a checkout by fast-forwarding `origin/main`, which rules out rebasing the fork onto upstream, and every server builds bb itself.
- Publish the fork to npm under another name. bb's update check and updater read the `bb-app` package by name, so the fork would need the same patch plus an npm publishing identity.

## Consequences

- Each setup run reinstalls whatever `bb-app-latest` points to; a broken fork release reaches the next server or prepared machine that runs setup, and a server's in-app updater may reach it first.
- A compromised fork release reaches servers and prepared machines, the same loss of setup-side detection ADR 0022 accepts for npm.
- Upstream releases reach machines only after the owner merges or rebases them into the fork.
- `tests/bb-server-contract.sh` and `tests/test_bb_machine_preparation.py` cover the package source and the version checks offline. Installing a real fork release on a server is unverified until a server runs setup.
