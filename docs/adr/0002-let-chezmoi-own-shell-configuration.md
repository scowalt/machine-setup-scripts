# Let Chezmoi own shell configuration

Chezmoi owns shell profiles; setup installs tools and applies managed dotfiles rather than maintaining a second copy of shell configuration. Installer-written profile edits can be overwritten by later dotfiles application, so installers must leave real profiles alone and runtime-activation repairs go through Chezmoi. The Linux Codex installer uses a disposable HOME to contain its profile edits while keeping the binary and application data in their intended account locations. The Antigravity CLI installer on macOS and Linux does the same with an explicit `--dir`; on Windows it runs with `--skip-path --skip-aliases`.

The boundary is exercised by the [Codex profile-isolation contract](../../tests/codex-profile-isolation-contract.sh), the [Antigravity CLI installation contract](../../tests/agy-installation-contract.sh) and [shared-runtime contract](../../tests/shared-node-runtime-contract.sh).
