#!/usr/bin/env bash
# Version 1 | Last changed: Keep native Codex installation out of shell profiles
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 "${repo_root}/tests/test_codex_profile_isolation.py"
