# Install the owner's desktop forks on headed Macs

macOS setup installs the owner's forks of the bb desktop app ([`scowalt/bb`](https://github.com/scowalt/bb)) and OmaCal ([`scowalt/omacal`](https://github.com/scowalt/omacal)) on every Apple Silicon [headed machine](../../GLOSSARY.md), so a new Mac needs no manual download of either. This supersedes [ADR 0017](0017-leave-bb-desktop-owner-managed.md) and the "desktop stays owner-managed" clause of [ADR 0022](0022-delegate-bb-trust-to-native-tools.md) for macOS only. Ubuntu, Bazzite, Pi, WSL and Windows still leave desktop applications to the owner.

Setup fills an empty slot and nothing more. It installs an application only when neither `/Applications` nor `~/Applications` has an entry of that name (a file, link or dangling link counts), so an existing official, custom or nightly copy, its links and its state are left exactly as found; setup only tests that the path exists. Both applications update themselves, so setup never upgrades them either. Exact `HEADLESS=1`, read after `~/.env.local` loads, skips the step, and every other value is a headed machine. `WORK_MACHINE` is not consulted.

ADR 0017 retired the installer after the [laptop B failure](../research/2026-10-16-macos-laptop-b-setup-failures.md), where setup refused to pick between `bb.app` in `/Applications` and in `~/Applications`. The new step avoids that failure by never choosing between copies: it does not discover, select, update or validate an installed desktop, and BB machine preparation and plugin refresh stay independent of it. Following ADR 0022 it adds no signature, notarization, ownership or mode gate, and it restores neither the retired installer nor [ADR 0006](0006-accept-native-macos-applications-for-bb-desktop.md)'s Applications transaction. A download is accepted when it unpacks to a bundle with the expected identifier and executable.

## Considered options

- Leave the forks owner-managed (ADR 0017). The owner then downloads and places both applications by hand on every new Mac.
- Restore the verified installer retired in `3c0d6df`. It required upstream's Developer ID identity and notarization, and neither fork has an Apple certificate: the bb fork is [self-signed and not notarized](https://github.com/scowalt/bb/blob/main/apps/desktop/README.md#fork-builds) and the OmaCal fork is [ad-hoc signed](https://github.com/scowalt/omacal/blob/main/.github/workflows/fork-macos.yml). It is also the machinery ADR 0022 removed.
- Install through a Homebrew cask. The owner publishes no public tap for either fork.

## Consequences

- Both forks publish arm64 builds only, so Intel Macs skip without error.
- Installed copies update themselves from the fork's own releases, so setup never upgrades one. bb's README says macOS installs an update only when it carries the installed build's signing identity. OmaCal's release workflow overrides the updater endpoint and key at build time, and fails the build unless the binary contains the fork's endpoint.
- The archives come over HTTPS from each fork's latest GitHub release with no checksum or signature check. A compromised fork release would reach newly set-up Macs, the same loss of setup-side detection that ADR 0022 accepts for the server paths.
- Setup downloads with `curl`, which sets no quarantine flag. OmaCal's workflow notes that `curl` and `gh` downloads are never seen by Gatekeeper and bb's README says the same of `gh release download`, while a browser download of either needs a manual override at first launch.
- A failed download, unpack or placement is reported and makes the run fail without stopping unrelated work. The two applications are independent, so one failing does not block the other.
- `/Applications` is used when the account can write to it, otherwise `~/Applications`.
- [`tests/test_desktop_forks.py`](../../tests/test_desktop_forks.py) validates the behavior offline. Gatekeeper, first launch and self-update on a real Mac are unverified until a Mac runs setup.
