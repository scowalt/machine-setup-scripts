#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 "${repo_root}/tests/test_headless.py"
python3 "${repo_root}/tests/test_macos_headless_homebrew.py"
