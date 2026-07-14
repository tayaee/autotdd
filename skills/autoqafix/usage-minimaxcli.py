#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""usage-minimaxcli — reports remaining MiniMax coding-plan usage for
autoqafix's LLM selection (docs/autoqafix-design.md "LLM 선정").

Output: one line of JSON with keys provider, five_hour_remaining_pct,
weekly_remaining_pct, effective_remaining_pct (= min of the two),
available. On any failure, still prints JSON with available:false and an
"error" field instead of writing to stderr, and still exits 0 -- callers
decide purely by parsing this line.

The minimax_quota() data-fetching logic below (cache path, TTL, and the
`mmx quota show` subprocess call) is copied from
~/git/harness-project/.local/bin/tmux-usage-bar.py's minimax_quota(),
per issue-8's instruction to reuse that data source as-is.
"""

import json
import os
import subprocess
import sys
import time

MINIMAX_CACHE = os.path.expanduser("~/.cache/mmx/usage.json")
MINIMAX_CACHE_TTL = 300  # seconds


# --- copied from tmux-usage-bar.py's minimax_quota(), trimmed to just the
# two utilization percentages this script needs ---
def minimax_quota() -> tuple[float, float]:
    """Return (interval_utilization_pct, weekly_utilization_pct)."""
    now = time.time()
    if not os.path.exists(MINIMAX_CACHE) or (now - os.path.getmtime(MINIMAX_CACHE)) > MINIMAX_CACHE_TTL:
        raw = subprocess.check_output(["mmx", "quota", "show", "--output", "json"], timeout=10)
        os.makedirs(os.path.dirname(MINIMAX_CACHE), exist_ok=True)
        with open(MINIMAX_CACHE, "wb") as f:
            f.write(raw)

    with open(MINIMAX_CACHE) as f:
        data = json.load(f)

    for model in data.get("model_remains", []):
        if model.get("model_name") == "general":
            return (
                100 - model.get("current_interval_remaining_percent", 100),
                100 - model.get("current_weekly_remaining_percent", 100),
            )
    raise RuntimeError("no 'general' model entry in minimax quota response")
# --- end copied ---


def main() -> None:
    fixture = os.environ.get("USAGE_FIXTURE")
    if fixture:
        with open(fixture) as f:
            sys.stdout.write(f.read().strip() + "\n")
        return

    try:
        interval_pct, weekly_pct = minimax_quota()
        interval_rem = 100 - interval_pct
        weekly_rem = 100 - weekly_pct
        result = {
            "provider": "minimaxcli",
            "five_hour_remaining_pct": interval_rem,
            "weekly_remaining_pct": weekly_rem,
            "effective_remaining_pct": min(interval_rem, weekly_rem),
            "available": True,
        }
    except Exception as e:
        result = {
            "provider": "minimaxcli",
            "five_hour_remaining_pct": 0,
            "weekly_remaining_pct": 0,
            "effective_remaining_pct": 0,
            "available": False,
            "error": str(e),
        }

    print(json.dumps(result))


if __name__ == "__main__":
    main()
