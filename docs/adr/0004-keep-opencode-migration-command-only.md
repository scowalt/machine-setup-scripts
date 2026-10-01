# Keep OpenCode migration verified and command-only

An existing `opencode` command can come from several installers; its name and reported version do not establish official artifact identity. Setup therefore matches official bytes before execution, stages a verified replacement, and quarantines only identified commands while retaining package stores, registrations, and application data for recovery. This deliberately leaves legacy registrations behind rather than running uninstall hooks or rewriting shared v1/v2 configuration during a CLI upgrade.

External package updates may recreate old command shims, requiring manual conflict resolution. The boundary and rollback live in the [shared installer](../../lib/opencode-cli.cjs) and [migration contracts](../../tests/opencode-cli.test.cjs).
