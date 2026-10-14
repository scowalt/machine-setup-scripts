# Offline Pi/adapter admission fixtures

These are unmodified MIT-licensed admission modules, not installed extensions:

- `vendor/adapter-project-server-trust.js`: [pi-mcp-adapter 5.3.0](https://cdn.jsdelivr.net/npm/pi-mcp-adapter@5.3.0/dist/project-server-trust.js), SHA-256 `5a7b9b6ad3152bcff260af21c14e70ddc312849ecf4a1bc393c3e1d946376ec0`.
- `vendor/pi-trust-manager.js`: [Pi 1.1.0](https://cdn.jsdelivr.net/npm/@earendil-works/pi-coding-agent@1.1.0/dist/core/trust-manager.js), SHA-256 `ce8644574983b5f8a04059545305b63463557cdf8d09049c35590cb937a70c76`.

The tests verify these bytes, then materialize temporary ESM copies. Only imports for profile/config constants, path/BOM helpers, the disabled predicate and the lock dependency are replaced with explicit fixture implementations. The lock replacement uses a real temporary `trust.json.lock` directory; it is not evidence for proper-lockfile's stale/heartbeat behavior. Production also refuses existing locks and bounds its synchronous transaction below the native stale interval.

Fresh processes run the captured native folder-trust reader and adapter admission routines against inert definitions and temporary native Git repositories/worktrees. Explicit test review calls `approveProjectServer` only inside that temporary profile. No Pi session engine, extension entry point, MCP server, credential integration, model or network is run. The doctor CLI is an inert test-authored executable that checks its exact arguments and returns synthetic JSON, including exit-zero `blocked` results. These tests establish offline admission/inheritance contracts, not live server connectivity or native platform rollout.

Run `tests/bb-pi-trust-contract.sh` only through the [audited contained fixture runner](../../../docs/research/2026-09-29-fixture-execution-audit.md), with existing native Node/PowerShell and mandatory kernel preflight. Native Windows ACL behavior remains separate platform evidence. Adjacent license files retain the upstream notices.
