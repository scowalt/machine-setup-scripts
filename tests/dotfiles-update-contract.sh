#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_dotfiles_update_failure.py

printf 'dotfiles update failure contract passed (no live setup or real checkout touched).\n'
