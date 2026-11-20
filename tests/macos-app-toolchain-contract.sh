#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_macos_app_toolchain.py

printf 'macOS app toolchain contract passed (mocked mise and Xcode tools; nothing installed).\n'
