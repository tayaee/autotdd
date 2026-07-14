@echo off
rem acpd default -- used only when the target project has no
rem run-pyright-full.bat of its own. Assumes CWD is already the target repo
rem root. Full pass: type-checks the whole project, unlike the src-only
rem run-pyright.bat.
echo === pyright (full project) ===
uv run pyright
