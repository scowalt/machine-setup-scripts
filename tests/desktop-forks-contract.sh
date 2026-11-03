#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_desktop_forks.py

printf 'desktop forks contract passed (mocked network and macOS tools; no application executed).\n'
