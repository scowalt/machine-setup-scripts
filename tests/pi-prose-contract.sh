#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

python3 tests/test_pi_prose_retirement.py
bash tests/pi-companion-packages-contract.sh

grep -Fq 'Preserve existing custom prose files' CLAUDE.md
printf '✓ pi-prose is retired without dependency resolution or custom-file changes\n'
