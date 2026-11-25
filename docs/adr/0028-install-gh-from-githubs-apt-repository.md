# Install gh from GitHub's apt repository

`ubuntu.sh`, `wsl.sh` and `pi.sh` used to install `gh` from the distribution archive. Ubuntu 26.04 and Debian trixie ship 2.46.0, and bookworm-based Raspberry Pi OS ships 2.23.0. Neither is updated. 2.46.0's `gh pr edit` fails on GitHub's retired Projects (classic) GraphQL fields, and it lacks newer flags such as `gh pr edit --attach` (2.102). GitHub's [Linux install guide](https://github.com/cli/cli/blob/trunk/docs/install_linux.md) says the community 2.45.x/2.46.x packages are broken and recommends its own apt repository.

These scripts now add that repository with the paths from GitHub's guide (`/etc/apt/keyrings/githubcli-archive-keyring.gpg`, checked against the SHA-256 the guide publishes, and `/etc/apt/sources.list.d/github-cli.list`). Each run refreshes only that source, runs `apt-get install gh`, and requires gh 2.102 or later. GitHub's package has the same name and a higher version, so apt replaces the distribution package in place at `/usr/bin/gh`. `mac.sh` and `bazzite.sh` keep Homebrew's `gh`, and `win.ps1` keeps WinGet's `GitHub.cli`. Those sources are current, and setup already upgrades them.

## Why not mise

A global mise selection (`gh = "latest"`) was the alternative. It was rejected for these reasons:

- `/usr/bin/gh` would remain, and every process that doesn't have mise's shims on PATH would still run 2.46.0. Examples are systemd units, `sudo`, cron and non-interactive shells. Two copies would stay, and the copy that runs would depend on the caller.
- mise resolves `latest` when it installs. A newer release needs a separate `mise upgrade`. apt picks up new releases on each setup run.
- Each platform already has one package manager that owns gh. This change uses that model on the apt platforms too.

A copy of `gh` that mise installed for `mise x` stays unselected, so mise's `gh` shim runs `/usr/bin/gh`. Setup doesn't remove it.

## Consequences

- If another source file already points at `cli.github.com/packages`, such as one from `extrepo` or `apt modernize-sources`, setup refreshes that file and removes its own `github-cli.list`. Two entries with different `Signed-By` paths would stop every apt command.
- A hold (`apt-mark hold gh`) is respected, and setup leaves `gh` unchanged.
- A failed download, checksum, apt update or install, or a `gh` older than 2.102, fails the setup result. Unrelated work still runs.
