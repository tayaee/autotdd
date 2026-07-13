#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["pydantic"]
# ///
"""log-cost-fable — fable(Claude) 단계의 cost_details 이벤트 기록.

check-usage --json의 "claude" row(five_hour/seven_day utilization)를
조회해 대상 이슈의 agent-stats.json cost_details에 이벤트를 append한다.
tdd2/autotddreview SKILL.md가 각 단계(mvp/review/refix-plan/refix) 전후에
호출한다.

사용법:
    log-cost-fable.py [--dryrun] <repo-path> <issue-N|autofix-N> "<description>"
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cost_entry import append_cost_detail, query_check_usage_pct  # noqa: E402

MODEL = "fable"
PROVIDER_KEY = "claude"


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else list(argv)
    dryrun = "--dryrun" in args
    if dryrun:
        args = [a for a in args if a != "--dryrun"]

    if len(args) != 3:
        print(f'Usage: log-cost-{MODEL}.py [--dryrun] <repo-path> <issue-N|autofix-N> "<description>"', file=sys.stderr)
        return 1

    repo = Path(args[0]).resolve()
    target, description = args[1], args[2]

    five_hour, seven_day = query_check_usage_pct(PROVIDER_KEY)
    try:
        path, entry = append_cost_detail(
            repo, target,
            model=MODEL,
            five_hour_used_pct=five_hour,
            seven_day_used_pct=seven_day,
            description=description,
            dryrun=dryrun,
        )
    except (FileNotFoundError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    prefix = "[dryrun] " if dryrun else ""
    print(f"{prefix}{path}")
    print(entry.model_dump_json(indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
