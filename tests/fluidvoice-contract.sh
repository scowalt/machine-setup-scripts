#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_fluidvoice.py

printf 'FluidVoice contract passed (mocked Homebrew and macOS tools; no application installed).\n'
