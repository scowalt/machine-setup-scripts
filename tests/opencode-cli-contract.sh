#!/usr/bin/env bash
# Version 1 | Last changed: Verify isolated OpenCode native policy and caller contracts
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 tools/embed-opencode-cli.py --check
node --test tests/opencode-cli.test.cjs
python3 tests/test_opencode_cli_callers.py
printf '%s\n' 'OpenCode CLI installation-only contracts passed (native rollout not exercised).'
