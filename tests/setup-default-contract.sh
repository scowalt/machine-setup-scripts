#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 "${repo_root}/tools/embed-setup-policy.py" --check
python3 "${repo_root}/tests/test_setup_rollback.py"
python3 "${repo_root}/tests/test_setup_environment.py"
