#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""usage-claudecli — reports remaining Claude Code coding-plan usage for
autoqafix's LLM selection (docs/autoqafix-design.md "LLM 선정").

Output: one line of JSON with keys provider, five_hour_remaining_pct,
weekly_remaining_pct, effective_remaining_pct (= min of the two),
available. On any failure, still prints JSON with available:false and an
"error" field instead of writing to stderr, and still exits 0 -- callers
decide purely by parsing this line.

The claude_usage() data-fetching logic below (cache path, TTL, and the
oauth/usage API call) is copied from
~/git/harness-project/.local/bin/tmux-usage-bar.py's claude_usage(),
per issue-8's instruction to reuse that data source as-is.
"""

import json
import os
import sys
import time
import urllib.request

CLAUDE_CREDS = os.path.expanduser("~/.claude/.credentials.json")
CLAUDE_USAGE_CACHE = os.path.expanduser("~/.cache/claude/usage.json")
CLAUDE_USAGE_CACHE_TTL = 60  # seconds


def _atomic_json_write(path: str, data) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


# --- copied from tmux-usage-bar.py's claude_usage(), trimmed to just the
# two utilization percentages this script needs ---
def claude_usage() -> tuple[float, float]:
    """Return (five_hour_utilization_pct, weekly_utilization_pct)."""
    now = time.time()
    os.makedirs(os.path.dirname(CLAUDE_USAGE_CACHE), exist_ok=True)
    cache_exists = os.path.exists(CLAUDE_USAGE_CACHE)
    if not cache_exists or (now - os.path.getmtime(CLAUDE_USAGE_CACHE)) > CLAUDE_USAGE_CACHE_TTL:
        with open(CLAUDE_CREDS) as f:
            token = json.load(f)["claudeAiOauth"]["accessToken"]
        req = urllib.request.Request(
            "https://claude.ai/api/oauth/usage",
            headers={"Authorization": f"Bearer {token}", "User-Agent": "claude-cli/2.1.191"},
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            data = json.loads(r.read())
        _atomic_json_write(CLAUDE_USAGE_CACHE, data)

    with open(CLAUDE_USAGE_CACHE) as f:
        data = json.load(f)

    five_h = data.get("five_hour", {}) or {}
    seven_d = data.get("seven_day", {}) or {}
    return round(five_h.get("utilization", 0)), round(seven_d.get("utilization", 0))
# --- end copied ---


def main() -> None:
    fixture = os.environ.get("USAGE_FIXTURE")
    if fixture:
        with open(fixture) as f:
            sys.stdout.write(f.read().strip() + "\n")
        return

    try:
        five_h_pct, weekly_pct = claude_usage()
        five_h_rem = 100 - five_h_pct
        weekly_rem = 100 - weekly_pct
        result = {
            "provider": "claudecli",
            "five_hour_remaining_pct": five_h_rem,
            "weekly_remaining_pct": weekly_rem,
            "effective_remaining_pct": min(five_h_rem, weekly_rem),
            "available": True,
        }
    except Exception as e:
        result = {
            "provider": "claudecli",
            "five_hour_remaining_pct": 0,
            "weekly_remaining_pct": 0,
            "effective_remaining_pct": 0,
            "available": False,
            "error": str(e),
        }

    print(json.dumps(result))


if __name__ == "__main__":
    main()
