#!/usr/bin/env bash
# Version 1 | Last changed: Prove legacy Paseo remains unmanaged with inert fixtures
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 "${repo_root}/tests/test_paseo_non_management.py"
