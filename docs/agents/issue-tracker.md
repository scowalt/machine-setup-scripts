# Issue tracker: GitHub

Issues and specs live in GitHub Issues for `scowalt/machine-setup-scripts`.
Use the `gh` CLI.

## Operations

- Create: `gh issue create --repo scowalt/machine-setup-scripts --title "..." --body-file <file>`
- Read: `gh issue view <number> --repo scowalt/machine-setup-scripts --comments`
- List: `gh issue list --repo scowalt/machine-setup-scripts --state open`
- Comment: `gh issue comment <number> --repo scowalt/machine-setup-scripts --body-file <file>`
- Label: `gh issue edit <number> --repo scowalt/machine-setup-scripts --add-label "..."`
- Close: `gh issue close <number> --repo scowalt/machine-setup-scripts --reason completed`

Use `--state all` when searching historical work and paginate exhaustive inventories.
Publishing to the issue tracker means creating a GitHub issue.
Fetching a relevant ticket includes its body, labels, and comments.

## Related work

Use native GitHub sub-issues and issue dependencies where available.
Otherwise, record reciprocal parent/child links and explicit `Blocked by: #N` lines.
For Wayfinder, label maps `wayfinder:map` and children `wayfinder:<type>`.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Migrated Backlog history

GitHub Issues is authoritative. Local `backlog/` files are frozen historical
snapshots, not an active tracker. The [migration index](https://github.com/scowalt/machine-setup-scripts/issues/99)
links every source record to its issue and preserves the original Backlog configuration.

Legacy task IDs are not GitHub issue numbers. Resolve them through the
migration index; some IDs identify multiple source records.
