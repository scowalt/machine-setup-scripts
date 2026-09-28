#!/usr/bin/env bash
# Version 2 | Last changed: Check independent Pi Go and package wiring without setup
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 "${repo_root}/tests/test_opencode_go_wiring.py"
