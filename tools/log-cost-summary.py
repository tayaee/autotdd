#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""log-cost-summary — cost_details를 스캔해 모델별 cost_summary를 계산.

aacpd(aacp.sh)가 `issue-N__TYPE-agent-stats.json`을 archive 디렉터리로
git mv하기 직전, `agent-stats-archive.py`보다 먼저 호출한다 — 이 시점엔
해당 이슈의 모든 LLM 작업(mvp/review/refix-plan/refix)이 이미 끝나 있다.
모델별로 five_hour_used_pct/seven_day_used_pct 합을 구해 cost_summary에
기록한다: null 값은 합산에서 제외하고, 어떤 모델의 특정 지표가 전부
null이면 합산 결과도 null로 남긴다(조회 불가였다는 사실 자체를 보존).

사용법:
    log-cost-summary.py [--dryrun] <repo-path> <issue-N|autofix-N>
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

STREAM_RE = re.compile(r"^(issue|autofix)-([0-9]+)$")


def parse_stream_id(value: str) -> tuple[str, str]:
    m = STREAM_RE.match(value)
    if not m:
        raise ValueError(f"스트림 ID 형식이 아님: {value!r} (issue-N 또는 autofix-N)")
    return m.group(1), m.group(2)


def find_stats_file(repo: Path, target: str) -> Path:
    stream, n = parse_stream_id(target)
    path = repo / "issues" / f"{stream}-{n}__agent-stats.json"
    if not path.is_file():
        raise FileNotFoundError(f"{path} 없음")
    return path


def _sum_or_null(values: list) -> float | None:
    present = [v for v in values if v is not None]
    if not present:
        return None
    return sum(present)


def compute_cost_summary(cost_details: list) -> dict:
    by_model: dict[str, dict[str, list]] = {}
    for entry in cost_details:
        model = entry.get("model", "unknown")
        bucket = by_model.setdefault(model, {"five_hour": [], "seven_day": []})
        bucket["five_hour"].append(entry.get("five_hour_used_pct"))
        bucket["seven_day"].append(entry.get("seven_day_used_pct"))

    return {
        model: {
            "five_hour_sum": _sum_or_null(v["five_hour"]),
            "seven_day_sum": _sum_or_null(v["seven_day"]),
        }
        for model, v in by_model.items()
    }


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else list(argv)
    dryrun = "--dryrun" in args
    if dryrun:
        args = [a for a in args if a != "--dryrun"]

    if len(args) != 2:
        print("Usage: log-cost-summary.py [--dryrun] <repo-path> <issue-N|autofix-N>", file=sys.stderr)
        return 1

    repo = Path(args[0]).resolve()
    try:
        path = find_stats_file(repo, args[1])
    except (ValueError, FileNotFoundError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        print(f"ERROR: {path} 객체 아님", file=sys.stderr)
        return 1

    cost_summary = compute_cost_summary(data.get("cost_details", []))

    prefix = "[dryrun] " if dryrun else ""
    if not dryrun:
        data["cost_summary"] = cost_summary
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"{prefix}{path}")
    print(json.dumps(cost_summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
