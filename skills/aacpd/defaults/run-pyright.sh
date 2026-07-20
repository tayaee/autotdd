#!/usr/bin/env bash
# aacpd default — used only when the target project has no
# ./run-pyright.sh of its own. Assumes CWD is already the target repo root.
# Quick pass: type-checks src/ only (falls back to the whole project if
# there's no src/ layout). For the whole project regardless, see
# run-pyright-full.sh.
set -euo pipefail
echo "=== pyright (src only) ==="
if [ -d src ]; then
    uv run pyright src
else
    uv run pyright .
fi
