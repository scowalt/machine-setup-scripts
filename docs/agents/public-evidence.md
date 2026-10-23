# Public operational evidence

Publish the diagnosis, not a machine inventory. Preserve failure predicates, operating-system and package versions, permission modes, chronology, validation results and uncertainty.

## Public copies

Use consistent synthetic role labels such as `development-server`, `linux-workstation`, `linux-desktop`, `macos-workstation`, `macos-laptop-a` and `macos-laptop-b`. These labels are not real hostnames or an authoritative fleet list. Keep any mapping to actual machines outside this public checkout.

- Use `.example.invalid` for connection-target and collector-link examples. Use RFC 5737 documentation ranges for IPv4 examples and RFC 3849 addresses for IPv6 examples.
- Replace real tailnet names/addresses, node IDs, host keys/fingerprints, hardware identifiers and host/account mappings in prose, commands, captured output, filenames and link targets.
- Refer to captured home directories as `$HOME`; use synthetic account names where a concrete example is necessary.
- Keep exact machine-specific collector URLs and raw evidence in private storage outside this checkout. A `logs.example.invalid` reference in a historical record preserves the object's timestamp, not a working download location. Authorized operators must resolve the real object from private evidence or the authenticated collector.
- Preserve legacy task status, dates, decisions and outcome claims when sanitizing historical snapshots; privacy edits are not new task progress or rollout evidence.

Generic account defaults in setup code, public package/repository identities, and the authenticated collector-access procedure are separate from captured machine inventory. Sanitizing records does not authorize changing those runtime contracts.

## Publication check

Review the complete staged diff, including renamed files, link targets and copied log/command excerpts. The public copy is ready when it retains the technical finding without identifying a real machine or publishing an executable target for it. Keep evidence that cannot be safely sanitized private.

Use the existing captured evidence for documentation cleanup. Fresh machine/service probes, credential retrieval, key rotation, rollout and Git history rewriting require their own scope; none is needed to redact a public record.
