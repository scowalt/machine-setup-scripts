# Retire the Scowalt engineering-skill suite

Setup no longer installs `scowalt/engineering-skills`, the owner's fork of the Matt Pocock skill suite. The owner now runs agents through pstack, a Pi package. Its playbooks cover the suite's prototype, bug-fix, architecture, review and TDD workflows. Several suite names, such as `tdd` and `teach`, also collided with pstack's skills. Every setup run removes the suite's copies offline, including user-modified copies, and there is no opt-out or reinstall path. As [ADR 0001](0001-keep-cleanup-for-retired-managed-tools.md) requires, the cleanup stays permanently.

`pr` is the exception. It follows the owner's PR-body conventions, and pstack has no equivalent, so the dotfiles now own `~/.agents/skills/pr` and the Claude Code copy. Setup never removes `pr` copies and drops only the suite's update records for it. Pi ownership now deduplicates only `pr`; setup removes the retired copies, so they need no exclusion rules.

## Consequences

As with other retirements, every later run removes the retired names from global skill directories. That includes a skill the owner later creates under a retired name such as `prototype` or `research`. Keep such a skill in a project, give it a new name, or add its name to the policy's kept list.

Removing the suite this way works no matter which repository merges first. Old setup runs that reinstall the suite overwrite `pr` with identical content. New runs keep whatever `pr` the dotfiles last applied.
