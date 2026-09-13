#!/usr/bin/env bash
# Version 1 | Last changed: Check Pi dependency recovery and truthful final results
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 "${repo_root}/tests/test_pi_package_maintenance.py"
