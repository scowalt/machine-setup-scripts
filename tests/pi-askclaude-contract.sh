#!/usr/bin/env bash
# Contract version 1: global AskClaude policy without removing Claude Bridge.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 tests/test_pi_askclaude.py
