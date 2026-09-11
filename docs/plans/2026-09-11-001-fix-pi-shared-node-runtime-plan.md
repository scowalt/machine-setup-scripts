---
title: "fix: Make Pi use a supported shared Node runtime after setup"
type: fix
status: completed
date: 2026-09-11
---

Task: TASK-17. Scott approved this plan after the planning interview. The setup and dotfiles changes are implemented locally, without a live rollout.

## Outcome

After setup, a new normal user shell at HOME selects a supported shared Node runtime and starts Pi. Setup must not report success based only on its temporary PATH.

Pi uses the same runtime as the shell and project tools. If a project explicitly selects an unsupported Node version, Pi operation in that project is outside this guarantee.

## Diagnosis and evidence

- The reported Node 18.19.1 runtime lacks `node:fs.globSync`.
- An isolated `pi --version` invocation reproduced that error under Node 18 and succeeded under Node 24.20.0.
- Installed Pi 0.85.1 declares Node >=22.19.0. All six setup helpers accept >=20.6.
- The helpers return early when inherited Node works, without establishing a supported global mise selection.
- The fallback writes a durable global selection, but its explicit `mise env ... node@24` does not prove ordinary shell selection.
- The inspected fish dotfiles template already activates mise. The inspected dotfiles source has no PowerShell mise activation template.
- The skills runtime helper runs before Pi and requires Node >=22.20. Its Node selection must agree with the shared-runtime policy.

Arcane was not contacted. Its exact global configuration, HOME overrides, and shell activation remain unverified.

## Agreed scope and behavior

1. Apply the shared-runtime policy to `mac.sh`, `ubuntu.sh`, `wsl.sh`, `pi.sh`, `bazzite.sh`, and `win.ps1`.
2. Preserve a global mise Node selection that meets the requirements of the managed tools. Do not upgrade it merely because a newer version exists.
3. If the global runtime is missing or unsupported, install and select a supported LTS runtime through mise.
4. For a new selection, prefer Node 24 on supported platforms and prebuilt Node 22 on Linux ARMv7. The ARMv7 selection must also satisfy the skills CLI minimum of 22.20.
5. Do not compile Node or use unofficial builds as a fallback. Report unsupported platforms without replacing the existing Pi installation.
6. Test Pi compatibility with Node >=22.19.0 and callable `fs.globSync`. Also make sure that npm is available under the selected shared runtime.
7. Test normal HOME resolution without forcing a Node version. If a HOME override conflicts, preserve it and report the conflict.
8. Keep the canonical npm Pi installation and normal Pi self-update and package commands. Do not add a private runtime, custom Pi launcher, private npm layout, or `npmCommand` adapter.
9. Add the required PowerShell mise activation in the separate dotfiles repository through chezmoi. Preserve unrelated profile content. Setup scripts must not write shell profiles.
10. Leave the existing fish template unchanged unless implementation tests establish a defect.
11. If runtime installation or validation fails, stop the Pi installation path before npm installation, uninstallation, or package-repair deletion.

The failure guarantee covers runtime preparation and validation. It does not include transactional rollback of subsequent npm package updates or extension changes.

## Preservation boundaries

Preserve system Node, project runtime pins, unrelated mise configuration, Pi preferences and credentials, existing `npmCommand` choices, and environment files. Do not change models, skills policy, Paseo release channels, or plugin migration behavior.

Changes apply on future setup runs. Do not run setup on arcane, perform a fleet rollout, apply live dotfiles, or restart a daemon during development.

## Implementation sequence

1. Add regression fixtures around extracted runtime and Pi installer functions. Reproduce the inherited-modern-Node case without a supported global selection.
2. Repair durable global selection and platform fallback. Align the earlier skills runtime helper so it cannot undo the policy or trigger ARMv7 compilation.
3. Activate the effective shared selection for setup and test fresh-shell selection at HOME without inherited runtime paths or an explicit Node-version override.
4. Add chezmoi-owned PowerShell activation in an isolated dotfiles worktree. Do not edit the live profile or apply dotfiles during development.
5. Put runtime validation before all Pi package mutations. Retain normal npm ownership of Pi commands.
6. Update setup script versions, relevant documentation, and task evidence. Review both repository diffs.

## Verification

Use temporary homes and isolated configuration. Extract tested functions rather than sourcing complete setup scripts.

- Node 18, early Node 22, missing `globSync`, and missing npm fail the appropriate readiness checks.
- Inherited Node 24 cannot hide a missing or unsupported global selection.
- A compatible global selection remains unchanged across repeated runs.
- A new fixture shell selects the supported runtime at HOME and can start Pi without setup's temporary environment.
- Conflicting HOME overrides and project Node 18 pins remain unchanged. An incompatible HOME override produces a clear failure.
- ARMv7 selects compatible prebuilt Node 22. Unsupported binary environments do not trigger compilation.
- Runtime download, activation, and validation failures cause no Pi npm mutations or repair deletions.
- PowerShell activation preserves unrelated profile behavior and handles missing mise safely.
- Existing Paseo runtime consumers still receive a compatible runtime. Do not change the embedded Paseo Plain installer unless a demonstrated dependency requires it.
- Run ShellCheck on modified Bash scripts, shell syntax checks, relevant existing contract tests, and PowerShell fixtures.

Python, Node, fish, and ShellCheck are available on the development host. Tests also used a portable PowerShell installation in a temporary directory. Native Windows, macOS, and ARM execution remain unverified.

If a required test cannot run, report the missing prerequisite and the checks that did run. Do not claim native-platform verification from Linux fixtures.

## Verification results

- All 23 Bash contract scripts passed, including the PowerShell fixtures reached through the new runtime contract.
- All 16 shared-runtime Python tests passed. An optional test also started the installed Pi CLI in an isolated fresh fish shell.
- The shared-runtime PowerShell suite passed 959 assertions and an isolated real-mise inventory fixture.
- Dotfiles passed 14 PowerShell profile tests and two existing model tests. Two native Windows profile tests were skipped on Linux.
- All 30 Paseo Plain setup tests passed with PowerShell enabled. The native Git-isolation fixture also passed with an explicitly supplied Paseo module.
- ShellCheck, Markdownlint, and whitespace checks passed for the changed files.

The existing `tests/setup-reliability-powershell.ps1` fails on Linux at its PR Lens path assertion on line 453. The same failure occurs against unmodified HEAD. This change leaves that unrelated test unchanged. The other existing PowerShell suites passed.

Dotfiles changes are in the sibling `tender-dolphin-dotfiles` worktree on branch `fix/pi-shared-node-runtime`. Deploy both repositories before expecting Windows activation. No setup ran on arcane, and no live dotfiles or daemon configuration changed.

## References

- `ubuntu.sh`: `pi_node_runtime_ready`, `ensure_pi_node_runtime`, the skills runtime helper, and `install_pi_cli`.
- `win.ps1`: `Test-PiNodeRuntimeReady`, `Enable-PiNodeRuntime`, and `Install-PiCli`.
- Dotfiles: `dot_config/private_fish/config.fish.tmpl`.
- [Node 24 release manifest](https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt).
- [Node 22 release manifest](https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt).
