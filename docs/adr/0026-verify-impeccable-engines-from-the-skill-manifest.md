# Verify Impeccable engines from the skill's checksum manifest

Impeccable 4.9.2 (engine 0.1.25, upstream PR #1375) stopped copying the native engine into each skill's `scripts/bin/<os>-<arch>/`. `install` now fills the launchers' version cache, `<IMPECCABLE_HOME or ~/.impeccable>/bin/<version>/`, and each launcher downloads and verifies a missing engine on first run against `scripts/engine-checksums.txt` beside it. Setup required the per-skill binary, so every run after the release failed with `phase=promotion reason=incomplete-payload` while the previous payload stayed in place. A `linux-workstation` run on 2026-11-16 shows the failure; its prior run, under 4.9.1, verified.

Promotion now requires `scripts/engine-checksums.txt` and accepts the payload when its line for `scripts/VERSION` and the native asset matches the `.sha256` published with that engine release. The launcher accepts only that digest, so a verified payload cannot run any other engine. A skill that still ships a bundled engine (an upstream offline bundle) must be executable and match the same digest, because the launcher prefers a sibling binary without checking it.

Setup does not copy the installer's staged cache into `~/.impeccable`. Isolation stays as it is: setup runs the installer in a disposable stage, and existing engine caches are preserved. As a result, setup no longer proves that an engine binary is present. The first Impeccable command on a machine downloads it, and it fails closed when offline or when the download doesn't match. Promotion replaces whole skill directories, so it removes the per-skill engines that older installs left behind.

Helpers that newer skill releases add, starting with `motion-reviewer`, are copied when the staged payload includes them and removed when it doesn't. The live universal bundle can lag the npm CLI by a release, so requiring a new helper would fail installs until the bundle catches up.

The contained regressions in `tests/test_impeccable_convergence.py` cover the manifest, bundled-engine and optional-helper cases. The first-run download remains native rollout evidence.
