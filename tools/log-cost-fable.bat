@echo off
rem uv run wrapper -- log-cost-fable.py declares a PEP 723 inline dependency on
rem pydantic, so it must be run via `uv run`, not plain `python`.
uv run "%~dp0log-cost-fable.py" %*
