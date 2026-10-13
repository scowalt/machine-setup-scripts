# Minith: Homebrew waiting on Keychain

## Captured evidence

On October 13, 2026, a headless Minith setup appeared stalled after Homebrew download results, a failed `brew link` step and a newer-CLT advisory. The owner supplied a process snapshot and a three-second native `sample`; no live setup or update was run during development.

The captured process chain was:

```text
brew.rb upgrade (85602)
  git credential-osxkeychain get (90391)
    git-credential-osxkeychain get (90408)
```

The credential helper had been running for about 99 minutes with no CPU activity. All 2,309 sampled stacks followed `SecItemCopyMatching` through Keychain content decryption to `SecurityServer::ClientSession::decrypt` and a Mach-message wait. This establishes the blocked credential-read boundary, not whether a particular approval dialog, locked keychain or Security-server problem caused it. Git was among the requested upgrades; whether its binary or authorization changed during this run was not captured.

The exact installed Homebrew version and its earlier `gh` lookup were not captured. [Current upstream credential resolution](https://github.com/Homebrew/brew/blob/main/Library/Homebrew/utils/github/api.rb) corroborates the path: an explicit Homebrew API token takes precedence over GitHub CLI credentials and the direct Git Keychain fallback. Changing Git's configured credential helper does not intercept that direct invocation. [GitHub CLI token lookup](https://github.com/cli/cli/blob/trunk/pkg/cmd/auth/token/token.go) uses the active account for the specified host; its [configuration implementation](https://github.com/cli/cli/blob/trunk/internal/config/config.go) can retrieve the credential from secure storage without an API validation request.

## Agreed behavior

The owner uses `gh auth login`, rather than requiring separate `GH_TOKEN` files. For exact `HEADLESS=1`, `mac.sh` establishes headless Homebrew authentication after the existing environment-loading preamble and before CLT bootstrap, desktop installation or any other provisioning. Failure refuses the entire setup with a nonzero result and existing log finalization. Logging, lock acquisition and the existing environment-file creation/migration preamble are not a zero-mutation boundary.

An already-exported native `HOMEBREW_GITHUB_API_TOKEN` override remains authoritative. Otherwise, one local `gh auth token --hostname github.com` lookup has a fixed ten-second deadline. Successful, bounded, single-token output is retained only in the setup-process environment for subsequent Homebrew commands; it is not written to a credential file or printed. Native GitHub CLI account/config/environment selection is preserved. There is no separate Scott-token selection, automated login or Keychain unlock/repair, Git configuration change, or network authentication preflight.

The private supervisor uses existing `/usr/bin/perl` core modules, a monotonic deadline, private captured stdout and discarded stderr. It starts an owned probe process group, bounds output, and waits for both stdout closure and command exit. Timeout, interruption or oversized output terminates only that owned probe/group with bounded reaping. Interpreter controls are removed; GitHub CLI prompts and update notifications are disabled. Shell tracing is suspended while handling the credential and restored afterward. Missing prerequisites, lookup failure, timeout and unusable output produce controlled diagnostics without echoing command output, exception text or secrets.

This is bounded credential acquisition, not a detector proving that no GUI dialog appeared. `gh` may itself contact Keychain; an inaccessible credential causes an early refusal instead of an indefinite provisioning-time wait. Cached credentials prevent Homebrew's later independent lookup. They remain visible to the setup process and its children, not isolated from the configured account. Successful retrieval does not prove token validity, permissions, network availability or package readiness: actual Homebrew failures still produce an incomplete setup run. Headed macOS, other platforms, ordinary directory trust and the [operation-result CLT policy](../adr/0007-use-operation-results-instead-of-clt-compatibility-gates.md) remain unchanged.

## Offline verification

`tests/test_macos_headless_homebrew.py` selects validated definitions only, installs inert commands and temporary account/config state before invoking the real macOS caller and final Homebrew update path. Its fake `brew upgrade` invokes a fake Git Keychain helper that sleeps if no cached credential exists. No real `gh`, Keychain, Homebrew, application or skill is executed.

- Red: `/tmp/setup-fixture-matrix-tmdt54bj` reproduced `brew upgrade → git credential-osxkeychain get → wait`; the caller exceeded the three-second fixture limit instead of refusing before provisioning.
- Initial green: `/tmp/setup-fixture-matrix-arjstcf5` passed that same regression after the guard was added.
- Extraction/default cohort: `/tmp/setup-fixture-matrix-4bj6b3zj` passed all three entries, including the mandatory containment/extraction contracts and setup-default contract.
- Core affected cohort: `/tmp/setup-fixture-matrix-yh3o70sb` passed all six entries: headless, CLT, Homebrew results, setup reliability, pending reboot and weekly regressions. The headless contract includes fifteen new methods covering a real ten-second timeout, ignored termination, inherited-output descendants, closed stdout with a live command, owned-group cleanup, failure/log propagation, exact flags, selected configuration preservation, output limits, tracing, explicit overrides and supervisor failures.

- Additional caller cohort: `/tmp/setup-fixture-matrix-aer227rf` passed AI-agent, BB desktop/preparation, Paseo preservation, shared Node and Pi profile-permission contracts. BB server exceeded the initial 300-second suite limit. The outer 900-second command expired during Pi package tests; the runner recorded seven completed entries, not a complete matrix. The remaining owned fixture group was identified by its private artifact stdio and stopped; no unrelated process was signaled.
- Bounded completion cohort: `/tmp/setup-fixture-matrix-zfx92iur` passed all five incomplete/not-yet-run entries with a 600-second per-suite limit: BB server, Pi package maintenance, Impeccable callers, OpenCode CLI and Go wiring. The original timeout/interruption artifacts remain intact. Pi package's two optional integrations and the native Windows npm command-shim case were skipped, not covered.
- Final targeted cohort after signal-ownership hardening: `/tmp/setup-fixture-matrix-3pzzp3i5` passed headless, containment/extraction, setup default, CLT and Homebrew results. The headless contract now includes sixteen new methods, adding inherited ignored-SIGCHLD coverage; the supervisor restores default child ownership and refuses to signal after ownership is lost.

Every behavioral cohort used the audited sequential runner with sanitized `env -i`, private roots/stdio and mandatory kernel filter/self-test, existing native Node and PowerShell, and no optional live integrations. Additional tools were explicit existing native mise, Chezmoi and Bun executable selections in `/tmp/mac-headless-fixture-tools.kDHhskjU`; no tool was installed. Bash syntax, ShellCheck and whitespace checks pass. Markdownlint is unavailable as a trusted installed command; documentation was reviewed manually. Optional external-dotfile/installed-code integrations and native-platform behavior are not claimed.

Native Apple Keychain/GUI behavior, macOS Perl/process-group behavior and a live Minith setup remain rollout evidence, not established by Linux fixtures. The separate [historical containment incident](2026-09-29-fixture-containment-incident.md) and its remote receipt/telemetry uncertainty are unchanged.
