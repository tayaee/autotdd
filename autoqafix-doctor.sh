#!/usr/bin/env bash
# autoqafix-doctor launcher (issue-20, issue-14 pattern).
set -euo pipefail

if ! command -v uv > /dev/null 2>&1; then
    echo "[원인] uv 없음"
    echo "[조치] curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 127
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/.claude/skills/autoqafix/autoqafix-doctor.py"

uv -q run "$PY_SCRIPT" --repo "$(pwd)" "$@"
