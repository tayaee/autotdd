@echo off
rem uv run wrapper -- log-cost-sonnet.py declares a PEP 723 inline dependency on
rem pydantic, so it must be run via `uv run`, not plain `python`.
uv run "%~dp0log-cost-sonnet.py" %*
