#!/usr/bin/env bash
# Contract version 2: isolated installs and native migration under poisoned Git hook variables.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "${repo_root}"

python3 tests/test_paseo_plain_setup.py

if [[ -n "${PASEO_TEST_PLUGIN_SERVICE_MODULE:-}" ]]; then
    python3 tests/test_paseo_native_fixture_isolation.py
else
    printf '%s\n' 'SKIP: native Paseo manager fixture needs PASEO_TEST_PLUGIN_SERVICE_MODULE; isolated CLI tests passed.'
fi
