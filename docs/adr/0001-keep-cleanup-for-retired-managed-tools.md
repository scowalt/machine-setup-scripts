# Keep cleanup for retired managed tools

RTK and Attention-kind are retired managed tools. Every setup run removes their managed footprints after the dotfiles apply step. Cleanup preserves foreign binaries, project files, unrelated settings, and unrelated agent content. This permanent cleanup permits either repository to deploy first. Setup stops if cleanup cannot separate managed state from user state. This limit prevents deletion of user content.

## Consequences

Cleanup code stays after active support is removed. Later manual integrations at setup-managed paths are also removed. Package-manager binaries remain when the setup scripts do not own them. Shared agent files remain after their managed blocks are removed, even when the files are empty.
