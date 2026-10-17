#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_bb_desktop.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_bb_desktop_callers.py

printf 'bb desktop non-management contract passed (no app or installer executed).\n'
