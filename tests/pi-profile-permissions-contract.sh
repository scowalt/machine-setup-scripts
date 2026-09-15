#!/usr/bin/env bash
# Offline fixtures only; never source setup entry points or run live Pi.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 "${ROOT}/tests/test_pi_profile_permissions.py"
