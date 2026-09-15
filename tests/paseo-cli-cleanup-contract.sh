#!/usr/bin/env bash
# Extracted CLI maintenance fixtures use temporary homes and never run live setup.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
PYTHONDONTWRITEBYTECODE=1 python3 "${repo_root}/tests/test_paseo_cli_cleanup.py"
