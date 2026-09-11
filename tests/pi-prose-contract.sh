#!/usr/bin/env bash
# Version 3 | Last changed: Retire pi-prose from global Pi profiles
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

# The Python fixtures extract only the retirement program and its wrappers.
# Set PWSH_BIN to include the Windows wrapper without loading full setup.
python3 tests/test_pi_prose_retirement.py
bash tests/pi-companion-packages-contract.sh

grep -Fq 'Setup removes the retired' README.md
grep -Fq 'Preserve existing custom prose files' CLAUDE.md
printf '✓ pi-prose is retired without dependency resolution or custom-file changes\n'
