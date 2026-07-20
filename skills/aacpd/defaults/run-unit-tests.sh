#!/usr/bin/env bash
# aacpd default — used only when the target project has no
# ./run-unit-tests.sh of its own. Assumes CWD is already the target repo
# root. Fast pass, no coverage.
set -euo pipefail
uv run pytest "$@"
