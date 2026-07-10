#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""usage-qwencli — local `qwen` service health check for autoqafix's LLM
selection (docs/autoqafix-design.md "LLM 선정"). Local models have no
usage/quota concept, so UP means fully available (100%) and DOWN means
unavailable (0%).

Output: one line of JSON with keys provider, five_hour_remaining_pct,
weekly_remaining_pct, effective_remaining_pct, available. Never writes to
stderr; always exits 0 -- callers decide purely by parsing this line.
"""

import json
import os
import shlex
import subprocess
import sys


def main() -> None:
    fixture = os.environ.get("USAGE_FIXTURE")
    if fixture:
        with open(fixture) as f:
            sys.stdout.write(f.read().strip() + "\n")
        return

    health_cmd = os.environ.get("QWEN_HEALTH_CMD", "qwen --version")
    error = None
    try:
        proc = subprocess.run(
            shlex.split(health_cmd),
            timeout=10,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        up = proc.returncode == 0
        if not up:
            error = f"health check exited {proc.returncode}"
    except Exception as e:
        up = False
        error = str(e)

    if up:
        result = {
            "provider": "qwencli",
            "five_hour_remaining_pct": 100,
            "weekly_remaining_pct": 100,
            "effective_remaining_pct": 100,
            "available": True,
        }
    else:
        result = {
            "provider": "qwencli",
            "five_hour_remaining_pct": 0,
            "weekly_remaining_pct": 0,
            "effective_remaining_pct": 0,
            "available": False,
            "error": error,
        }

    print(json.dumps(result))


if __name__ == "__main__":
    main()
