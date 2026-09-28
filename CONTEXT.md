# Machine Setup

The machine setup context defines the desired development environment on each supported platform. The scripts converge each machine to this state.

## Language

**Desired machine state**:
The set of tools and artifacts that must be present or absent after a setup run.
_Avoid_: Target configuration, final setup

**Incomplete setup run**:
A setup run with a failed required operation or an unverified required result. Intentional user exclusions and expected Paseo deferrals do not by themselves make the run incomplete.
_Avoid_: Successful setup with errors, warning-only failure

**Work machine**:
A supported machine classified for employer-related development. Work-only managed tools are part of its desired machine state; on other machines, those tools remain unmanaged.
_Avoid_: Corporate machine, office machine

**Gitea client**:
The Tea command-line client used from a workstation to interact with Gitea instances.
_Avoid_: Gitea CLI, Gitea server command

**Managed tool**:
A development tool whose installation, configuration, update, and removal are controlled by the setup scripts.
_Avoid_: Provisioned tool, setup tool

**bb server**:
An independent main application server for the bb agentic IDE published by get-bb/bb, with its own projects and sessions. It is distinct from BBEdit and from an execution machine enrolled with another bb server.
_Avoid_: BBEdit server, bb execution machine

**bb execution machine**:
A machine enrolled with a bb server to host project files and run agents. Enrollment does not make it an independent bb server.
_Avoid_: Secondary bb server, browser client

**bb machine daemon**:
The local background component connecting a bb execution machine to its bb server. It is distinct from the main application server.
_Avoid_: Main server, browser client

**bb machine preparation**:
Installation of the local software needed for later manual enrollment as a bb execution machine. A prepared machine is not necessarily enrolled, running a daemon, or reachable from a server.
_Avoid_: Pairing, connected machine

**bb machine enrollment**:
The authorized association of an execution machine with a particular bb server. Installing software alone does not establish this association.
_Avoid_: Daemon installation, machine discovery

**Shared Node runtime**:
The user-level Node runtime used by managed tools and projects without a runtime override. A project-specific selection takes precedence.
_Avoid_: System Node, Pi-only runtime

**Managed Paseo profile**:
A named Paseo agent launch choice included in the desired machine state. Its managed core consists of the agent provider, model, and reasoning level.
_Avoid_: Agent instance, Desktop preference

**Expected Paseo deferral**:
A managed Paseo operation deliberately postponed because Desktop owns the local daemon or setup is running inside it. The reason is established, rather than an unresolved safety check.
_Avoid_: Ownership verification failure, completed profile update

**Unverified Paseo safety check**:
A check that lacks trustworthy evidence to determine whether a managed profile or daemon change would conflict with a running owner or writer. It is distinct from an expected Paseo deferral.
_Avoid_: Expected deferral, proof that no daemon is running

**Surplus Paseo CLI installation**:
A verified redundant global Paseo CLI installation in a known package-manager location, separate from the retained CLI. Age or version alone does not establish this status.
_Avoid_: Abandoned Paseo, old Paseo

**OpenCode Go subscription**:
A coding subscription that provides model access for Pi. It is distinct from paid OpenCode Zen usage and the OpenCode CLI.
_Avoid_: OpenCode installation, Zen subscription

**Muse Spark 1.3 Contributor**:
The Muse model offering available through OpenCode Go. Its terms permit retention of prompts and responses and their use for model training.
_Avoid_: Muse 1.3 paid, Muse Zen

**Pi package**:
A registered bundle of Pi extensions, skills, prompts, or themes. Packages may be setup-managed or user-added.
_Avoid_: Extension file, Pi installation

**Active global Pi profile**:
The single user-level Pi configuration selected for a setup run. It is distinct from project-scoped configuration and other global profiles.
_Avoid_: All Pi profiles, project profile

**Pi package refresh**:
An update of registered packages in the active global Pi profile, including setup-managed and user-added packages. It is distinct from updating Pi itself.
_Avoid_: Pi self-update, extension reload

**Disabled Pi resource**:
An extension, skill, prompt, or theme excluded from activation while its containing package remains registered. A disabled resource is distinct from an excluded package.
_Avoid_: Removed package, package opt-out

**Pi package exclusion**:
An intentional setup policy requiring a package to be absent, such as a supported user opt-out or managed retirement. It is distinct from disabling resources within an installed package.
_Avoid_: Disabled extension, resource filter

**Pi output style**:
A named preference for how Pi writes responses. A user default starts new sessions unless a session, command-line, or project choice overrides it.
_Avoid_: Prose mode, writing preset

**Managed agent skill**:
An agent skill whose upstream identity and managed footprint are part of the desired machine state. User-created and project-scoped skills are outside this category.
_Avoid_: Setup-managed skill, bundled skill

**PR Lens skill**:
A retired agent skill that draws code changes or system structure as architecture and data-flow diagrams. It is distinct from the PR Lens GitHub App.
_Avoid_: PR review bot, PR Lens app

**Managed footprint**:
The files, directories, configuration entries, and environment entries that the setup scripts own for a managed tool.
_Avoid_: Installation, tool data

**Retired managed tool**:
A former managed tool whose managed footprint must be absent from the desired machine state.
_Avoid_: Banned tool, removed tool

**Attention-kind guidance**:
A retired managed tool that changed agent responses across supported AI coding harnesses.
_Avoid_: Attention system agent, Attention plugin

**Shared agent file**:
An agent file that can contain both managed text and user text.
_Avoid_: Managed file, configuration blob

**Pending reboot**:
The machine state in which already-applied updates only take effect after a restart. Detection is best-effort per platform. On WSL it refers to a restart of the WSL instance, not of the Windows host.
_Avoid_: Restart required, reboot flag
