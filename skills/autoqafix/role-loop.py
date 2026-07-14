#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""role-loop — thin periodic loop for a single role (issue-19).

Runs one role's one-shot (qa → autoqa.py, fix → autofix.py,
dev → autofix.py --stream issue) forever, keeping a minimum interval
between round starts (AUTOQAFIX_INTERVAL, default 21600s = 6h; --interval
overrides). No boot wait — that belongs to the composite autoqafix-loop
(issue-18). Test injection: AUTOQAFIX_ROLE_CMD replaces the one-shot with
a shell command.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_INTERVAL_SEC = 21600
POLL_MAX_SEC = 60.0

ROLES = ("qa", "fix", "dev")


def role_cmd(role: str, repo: Path) -> list[str]:
    if role == "qa":
        return [sys.executable, str(SCRIPT_DIR / "autoqa.py"), "--repo", str(repo)]
    if role == "fix":
        return [sys.executable, str(SCRIPT_DIR / "autofix.py"), "--repo", str(repo)]
    return [
        sys.executable, str(SCRIPT_DIR / "autofix.py"),
        "--repo", str(repo), "--stream", "issue",
    ]


def run_round(role: str, repo: Path) -> int:
    injected = os.environ.get("AUTOQAFIX_ROLE_CMD")
    if injected:
        proc = subprocess.run(injected, shell=True, cwd=repo)
    else:
        proc = subprocess.run(role_cmd(role, repo), cwd=repo)
    return proc.returncode


def wait_until_interval(last_start: float, interval_sec: float) -> None:
    """Sleep in short slices until interval_sec has elapsed since
    last_start (time.monotonic()). Sliced so signals/kill land fast and
    a future composite loop can reuse this between phases."""
    while True:
        remaining = interval_sec - (time.monotonic() - last_start)
        if remaining <= 0:
            return
        time.sleep(min(POLL_MAX_SEC, remaining))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=str, help="Repository root path")
    parser.add_argument("--role", required=True, choices=ROLES)
    parser.add_argument(
        "--interval", type=int, default=None,
        help=f"round interval in seconds (default: AUTOQAFIX_INTERVAL or {DEFAULT_INTERVAL_SEC})",
    )
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    interval_sec = args.interval
    if interval_sec is None:
        interval_sec = int(os.environ.get("AUTOQAFIX_INTERVAL", str(DEFAULT_INTERVAL_SEC)))

    print(f"[role-loop] role={args.role} interval={interval_sec}s repo={repo}", flush=True)
    while True:
        round_start = time.monotonic()
        rc = run_round(args.role, repo)
        print(f"[role-loop] role={args.role} rc={rc}", flush=True)
        wait_until_interval(round_start, interval_sec)


if __name__ == "__main__":
    main()
