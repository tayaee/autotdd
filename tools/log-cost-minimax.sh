#!/usr/bin/env bash
# uv run wrapper -- log-cost-minimax.py declares a PEP 723 inline dependency on
# pydantic, so it must be run via `uv run`, not plain `python3`
# (which would fail with ModuleNotFoundError unless pydantic happens to
# already be installed in the ambient interpreter). Resolves its own
# directory so it works regardless of the caller's CWD.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec uv run "$SCRIPT_DIR/log-cost-minimax.py" "$@"
