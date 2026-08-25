# Machine Setup

The machine setup context defines the desired development environment on each supported platform. The scripts converge each machine to this state.

## Language

**Desired machine state**:
The set of tools and artifacts that must be present or absent after a setup run.
_Avoid_: Target configuration, final setup

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
