#!/usr/bin/env bash
# autodev-loop launcher — role-loop.py --role dev (issue-19, issue-14 pattern).
set -euo pipefail

if ! command -v uv > /dev/null 2>&1; then
    echo "[원인] uv 없음"
    echo "[조치] curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 127
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/.claude/skills/autoqafix/role-loop.py"

uv -q run "$PY_SCRIPT" --repo "$(pwd)" --role dev "$@"
