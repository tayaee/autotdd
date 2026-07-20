@echo off
rem aacpd default -- used only when the target project has no
rem run-unit-tests.bat of its own. Assumes CWD is already the target repo root.
uv run pytest %*
