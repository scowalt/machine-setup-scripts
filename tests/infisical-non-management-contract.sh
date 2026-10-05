#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"
python3 tests/test_infisical_non_management.py
printf '✓ Infisical non-management offline contract passed\n'
