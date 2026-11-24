# Rerun setup when bb is idle

A bb server host runs setup unattended, so `ubuntu.sh` with exact `HEADLESS=1` and `BB_SERVER=1` installs `setup-autorun`. It is a user timer that runs the published `ubuntu.sh` only while no bb thread is `pending`, `starting`, `active` or `stopping`. A setup run can update the bb package and restart the server, and the restart interrupts every running thread, including threads on other hosts that use this server. Waiting for idle avoids that. Scheduling by time of day doesn't, because agents run at all hours.

The design comes from a copy installed by hand on scott-beelink-ubuntu, which ran it from 2026-11-07 before setup managed it.

## Behaviour

- `setup-autorun.timer` checks 10 minutes after boot, then 10 minutes after each check ends.
- A check runs the script only if the download succeeded, starts with `#!` and bb reports no running thread. The check lists every thread with an explicit `--limit`, because `bb thread list` returns only 200 by default in an order that isn't recency, and fails closed if the list could have been cut short. Before this, a host with over 200 threads ran setup while threads further down the list were running (a `development-server` in Nov 2026 had 1 of its 12 running threads in the first 200). It also needs either a script hash never attempted before or a last attempt at least an hour old. If bb can't be queried, or another setup run holds `machine-setup.lock`, the check skips without recording an attempt.
- The attempt is recorded before the script starts, so a failing or hung run waits an hour before it is retried. `TimeoutStartSec=45min` stops a hung run, and `flock` prevents overlapping checks.
- The script runs with stdin from `/dev/null` and no terminal, so its `/dev/tty` prompts fail at once. Its sudo steps need passwordless sudo, which `HEADLESS=1` with `HEADLESS_PASSWORDLESS_SUDO=1` configures. Without it, those steps fail and the run reports errors.
- State is in `~/.local/state/setup-autorun/`. `runs.tsv` records every run, and `setup-autorun --dry-run` prints the next decision. Output goes to `journalctl --user -u setup-autorun`.

## Consequences

- Setup replaces the runner and units by rename. A running check keeps reading the bytes it started with when the run it started rewrites them.
- Setup enables the timer only when it creates the timer file. If `daemon-reload` or the enable fails, setup removes the new timer file so the next run tries again. After `systemctl --user disable --now setup-autorun.timer`, later runs keep the files current but leave the timer off.
- Setup leaves the timer in place when `BB_SERVER` is unset or 0, like the rest of the server's state.
- Reruns read `HEADLESS` and `BB_SERVER` from `~/.env.local` only. Setting them on the command line installs the timer, but later reruns then take the machine-preparation path, so set them in `~/.env.local`.
- The idle check happens once, before the run. A thread that starts later in the run can still be interrupted if the run restarts bb. bb is stopped after the other installers finish, about a minute into a typical run and up to ten minutes into a heavy one.
- The setup log watcher opens a diagnostic thread for a failed run, and that thread delays the next run until it finishes.
- If a run leaves bb stopped, later checks can't list threads and skip, so the rerun can't repair bb. Restart bb by hand.
