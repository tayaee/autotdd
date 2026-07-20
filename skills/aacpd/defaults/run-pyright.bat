@echo off
rem aacpd default -- used only when the target project has no
rem run-pyright.bat of its own. Assumes CWD is already the target repo root.
rem Quick pass: type-checks src\ only. See run-pyright-full.bat for the
rem whole project.
echo === pyright (src only) ===
if exist src (
    uv run pyright src
) else (
    uv run pyright .
)
