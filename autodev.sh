#!/usr/bin/env bash
# autodev launcher — same as autofix.sh but pinned to the `issue` stream
# (see autofix.py STREAMS / stream_to_role: `issue` → role `dev`).
# Mirrors autoqa.sh pattern (issue-14).
set -euo pipefail

if ! command -v uv > /dev/null 2>&1; then
    echo "[원인] uv 없음"
    echo "[조치] curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 127
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/.claude/skills/autoqafix/autofix.py"

uv -q run "$PY_SCRIPT" --repo "$(pwd)" --stream issue