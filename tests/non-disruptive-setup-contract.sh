#!/usr/bin/env bash
# Version 1 | Last changed: Exercise default setup protection through real callers
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 "${repo_root}/tools/embed-setup-policy.py" --check
python3 "${repo_root}/tests/test_non_disruptive_setup.py"
