#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""reviewer-scoreboard — 리뷰어별 판정 이력 스코어보드 CLI (issue-43).

autotddreview의 플래너(issue-41)가 사이클마다 남기는
`issues/issue-N__TYPE-review-stats.json`을 라이브·아카이브에서 모두 모아
리뷰어(base 모델명)별로 집계한다. 표준 라이브러리만 사용.

사용법:
    reviewer-scoreboard.py [repo-path] [--json] [--since YYYY-MM-DD]
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime
from pathlib import Path

COUNT_KEYS = ("findings", "must_fix", "good_to_fix", "gate_rejected", "verify_rejected")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="리뷰어별 review-stats JSON 집계")
    p.add_argument("repo", nargs="?", default=".", help="대상 리포 경로 (기본: cwd)")
    p.add_argument("--json", action="store_true", dest="as_json", help="기계용 JSON 출력")
    p.add_argument("--since", type=date.fromisoformat, default=None,
                   metavar="YYYY-MM-DD", help="해당 일자 이후 사이클만 집계")
    return p.parse_args(argv)


def collect(repo: Path, since: date | None) -> tuple[dict[str, dict[str, int]], int]:
    """issues/ + issues/archive/ 재귀 수집·집계. 손상 파일은 경고 후 계속."""
    issues_dir = repo / "issues"
    stats: dict[str, dict[str, int]] = {}
    cycles = 0
    for f in sorted(issues_dir.rglob("*__TYPE-review-stats.json")):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
            reviewers = data["reviewers"]
            if not isinstance(reviewers, dict):
                raise ValueError("reviewers 필드가 객체가 아님")
        except Exception as exc:
            print(f"경고: {f} 파싱 불가 — 건너뜀 ({exc})", file=sys.stderr)
            continue
        if since is not None:
            try:
                when = datetime.fromisoformat(str(data.get("date", ""))).date()
            except ValueError:
                print(f"경고: {f} date 필드 해석 불가 — 건너뜀", file=sys.stderr)
                continue
            if when < since:
                continue
        cycles += 1
        for name, r in reviewers.items():
            agg = stats.setdefault(str(name), {"cycles": 0, **{k: 0 for k in COUNT_KEYS}})
            agg["cycles"] += 1
            if isinstance(r, dict):
                for k in COUNT_KEYS:
                    try:
                        agg[k] += int(r.get(k, 0))
                    except (TypeError, ValueError):
                        print(f"경고: {f} {name}.{k} 값 비정상 — 0으로 처리", file=sys.stderr)
    return stats, cycles


def promotion_rate(agg: dict[str, int]) -> float:
    if agg["findings"] <= 0:
        return 0.0
    return (agg["must_fix"] + agg["good_to_fix"]) / agg["findings"]


def render_table(stats: dict[str, dict[str, int]], cycles: int) -> str:
    rows = sorted(stats.items(), key=lambda kv: promotion_rate(kv[1]), reverse=True)
    header = f"{'리뷰어':<12} {'사이클':>6} {'finding':>8} {'must':>5} {'good':>5} {'gate-rej':>8} {'verify-rej':>10} {'승격률':>7}"
    lines = [f"집계 사이클: {cycles}", header, "-" * len(header)]
    for name, agg in rows:
        lines.append(
            f"{name:<12} {agg['cycles']:>6} {agg['findings']:>8} {agg['must_fix']:>5} "
            f"{agg['good_to_fix']:>5} {agg['gate_rejected']:>8} {agg['verify_rejected']:>10} "
            f"{promotion_rate(agg) * 100:>6.1f}%"
        )
    lines.append("")
    lines.append("해석: 승격률이 지속적으로 낮은 리뷰어는 교체 후보 — 단 표본(사이클·finding)이 적으면 판단 유보.")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    repo = Path(args.repo).resolve()
    issues_dir = repo / "issues"
    if not issues_dir.is_dir():
        print(f"ERROR: {issues_dir} 디렉토리가 없습니다 — 대상 리포가 맞습니까?", file=sys.stderr)
        return 1

    stats, cycles = collect(repo, args.since)

    if args.as_json:
        payload = {
            "cycles": cycles,
            "reviewers": {
                name: {**agg, "promotion_rate": promotion_rate(agg)}
                for name, agg in stats.items()
            },
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    if not stats:
        print("집계할 review-stats JSON이 없습니다.")
        return 0

    print(render_table(stats, cycles))
    return 0


if __name__ == "__main__":
    sys.exit(main())
