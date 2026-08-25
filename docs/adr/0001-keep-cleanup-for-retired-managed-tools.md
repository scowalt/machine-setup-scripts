# Keep cleanup for retired managed tools

RTK is a retired managed tool. Every setup run removes its managed footprint after the dotfiles apply step. The cleanup preserves foreign binaries, project files, and unrelated agent content. This permanent cleanup permits either repository to deploy first. The setup stops if cleanup cannot separate managed text from user text. This limit prevents deletion of user content.

## Consequences

Cleanup code stays after active RTK support is removed. Later manual RTK integrations and data are also removed. A package-manager binary remains because the setup scripts do not own it.
