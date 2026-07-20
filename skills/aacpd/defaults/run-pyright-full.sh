#!/usr/bin/env bash
# aacpd default — used only when the target project has no
# ./run-pyright-full.sh of its own. Assumes CWD is already the target repo
# root. Full pass: type-checks the whole project (no path restriction),
# unlike the src-only run-pyright.sh. Slower — meant as a final gate, not a
# tight inner loop.
set -euo pipefail
echo "=== pyright (full project) ==="
uv run pyright
