#!/usr/bin/env bash
# aacpd default — used only when the target project has no ./run-ruff.sh
# of its own. Unlike a project-local copy, this does NOT cd to its own
# directory: aacpd's deploy.sh already ensures CWD is the target repo root.
set -euo pipefail
echo "=== ruff check --fix ==="
uv run ruff check --fix
