#!/usr/bin/env bash
# autofix launcher — mirrors autoqa.sh pattern (issue-14): detect uv,
# locate autofix.py relative to this script's dir, exec via `uv -q run`.
# Stream defaults to autofix (see autofix.py STREAM_DEFAULT).
set -euo pipefail

if ! command -v uv > /dev/null 2>&1; then
    echo "[원인] uv 없음"
    echo "[조치] curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 127
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/.claude/skills/autoqafix/autofix.py"

uv -q run "$PY_SCRIPT" --repo "$(pwd)"