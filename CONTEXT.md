# Machine Setup

The machine setup context defines the desired development environment on each supported platform. The scripts converge each machine to this state.

## Language

**Desired machine state**:
The set of tools and artifacts that must be present or absent after a setup run.
_Avoid_: Target configuration, final setup

**Work machine**:
A supported machine classified for employer-related development. Work-only managed tools are part of its desired machine state; on other machines, those tools remain unmanaged.
_Avoid_: Corporate machine, office machine

**Gitea client**:
The Tea command-line client used from a workstation to interact with Gitea instances.
_Avoid_: Gitea CLI, Gitea server command

**Managed tool**:
A development tool whose installation, configuration, update, and removal are controlled by the setup scripts.
_Avoid_: Provisioned tool, setup tool

**Managed footprint**:
The files, directories, configuration entries, and environment entries that the setup scripts own for a managed tool.
_Avoid_: Installation, tool data

**Retired managed tool**:
A former managed tool whose managed footprint must be absent from the desired machine state.
_Avoid_: Banned tool, removed tool

**Shared agent file**:
An agent file that can contain both managed text and user text.
_Avoid_: Managed file, configuration blob

**Pending reboot**:
The machine state in which already-applied updates only take effect after a restart. Detection is best-effort per platform. On WSL it refers to a restart of the WSL instance, not of the Windows host.
_Avoid_: Restart required, reboot flag
