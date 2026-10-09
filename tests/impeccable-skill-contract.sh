#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"
python3 tests/test_impeccable_diagnostics.py
python3 tests/test_impeccable_convergence.py
python3 tests/test_impeccable_staging_permissions.py
python3 tests/test_impeccable_embedding.py
