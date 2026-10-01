#!/usr/bin/env bash
# Version 1 | Last changed: Guard system Bash parsing and literal helper stdin
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 tests/test_bash_compatibility.py
