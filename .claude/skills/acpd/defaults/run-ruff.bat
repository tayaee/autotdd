@echo off
rem acpd default -- used only when the target project has no
rem run-ruff.bat of its own. Assumes CWD is already the target repo root.
echo === ruff check --fix ===
uv run ruff check --fix
