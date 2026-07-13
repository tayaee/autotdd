#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""reviewer-scoreboard — 리뷰어/구현자 스코어보드 CLI (issue-43, issue-45).

autotddreview의 플래너(issue-41)가 사이클마다 남기는
`issues/issue-N__TYPE-review-stats.json`과 tdd2 coder 측(issue-45)이
남기는 `issues/issue-N__TYPE-coder-stats.jsonl`을 라이브·아카이브에서
모두 모아 모델별로 집계한다. 표준 라이브러리만 사용.

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

_EMPTY_CODER: dict[str, int | str | set[int]] = {
    "issues": set(),       # type: ignore[assignment]
    "runs": 0,
    "errors": 0,
    "fixed": 0,
    "syntax_errors": 0,
    "loc_added": 0,
    "model": "",
}


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="리뷰어/구현자 review-stats + coder-stats 집계")
    p.add_argument("repo", nargs="?", default=".", help="대상 리포 경로 (기본: cwd)")
    p.add_argument("--json", action="store_true", dest="as_json", help="기계용 JSON 출력")
    p.add_argument("--since", type=date.fromisoformat, default=None,
                   metavar="YYYY-MM-DD", help="해당 일자 이후 사이클만 집계")
    return p.parse_args(argv)


def _parse_iso_date(value: object) -> date | None:
    """ISO 8601 문자열을 date로. 파싱 실패 시 None (조용히)."""
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value).date()
    except ValueError:
        return None


def collect(repo: Path, since: date | None) -> tuple[dict[str, dict[str, int]], int]:
    """리뷰어 review-stats JSON을 재귀 수집·집계. 손상 파일은 경고 후 계속."""
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
            when = _parse_iso_date(data.get("date"))
            if when is None:
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


def collect_coders(repo: Path, since: date | None) -> dict[str, dict]:
    """구현자 coding-stats JSON을 재귀 수집·집계.

    손상 파일/누락 필드는 stderr 경고 후 계속(침묵 금지).
    """
    issues_dir = repo / "issues"
    stats: dict[str, dict] = {}
    for f in sorted(issues_dir.rglob("*__TYPE-coding-stats.json")):
        stem = f.stem
        prefix = "issue-"
        idx = stem.find(prefix)
        if idx == -1:
            print(f"경고: {f} 파일명에서 이슈 번호 추출 불가 — 건너뜀", file=sys.stderr)
            continue
        rest = stem[idx + len(prefix):]
        digits = ""
        for ch in rest:
            if ch.isdigit():
                digits += ch
            else:
                break
        if not digits:
            print(f"경고: {f} 파일명에서 이슈 번호 추출 불가 — 건너뜀", file=sys.stderr)
            continue
        issue_n = int(digits)
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except Exception as exc:
            print(f"경고: {f} 파싱 불가 — 건너뜀 ({exc})", file=sys.stderr)
            continue
        if not isinstance(data, dict):
            print(f"경고: {f} 객체 아님 — 건너뜀", file=sys.stderr)
            continue
        coders = data.get("coders")
        if not isinstance(coders, dict):
            print(f"경고: {f} 'coders' 필드가 없거나 객체가 아님 — 건너뜀", file=sys.stderr)
            continue
        for coder_id, coder_data in coders.items():
            if not isinstance(coder_data, dict):
                print(f"경고: {f} coder {coder_id} 데이터가 객체가 아님 — 건너뜀", file=sys.stderr)
                continue
            model = coder_data.get("model")
            if not isinstance(model, str) or not model:
                print(f"경고: {f} coder {coder_id}에 model 필드 없거나 빈 문자열 — 건너뜀", file=sys.stderr)
                continue
            mvp = coder_data.get("mvp")
            review_outcome = coder_data.get("review_outcome")
            mvp_date = None
            review_date = None
            if isinstance(mvp, dict):
                mvp_date = _parse_iso_date(mvp.get("ts"))
            if isinstance(review_outcome, dict):
                review_date = _parse_iso_date(review_outcome.get("ts"))
            dates = [d for d in (mvp_date, review_date) if d is not None]
            if since is not None:
                if not dates or max(dates) < since:
                    continue
            agg = stats.setdefault(coder_id, _empty_coder_dict())
            agg["issues"].add(issue_n)
            agg["model"] = model
            if isinstance(mvp, dict):
                loc = mvp.get("loc_added", 0)
                try:
                    agg["loc_added"] += int(loc) if loc is not None else 0
                except (TypeError, ValueError):
                    print(f"경고: {f} coder {coder_id} mvp.loc_added 값 비정상 — 0으로 처리", file=sys.stderr)
                saf = mvp.get("static_analysis_failures")
                if isinstance(saf, dict):
                    for tool in ("ruff", "pyright"):
                        val = saf.get(tool)
                        if val is not None:
                            try:
                                val_int = int(val)
                                if agg["static_analysis_failures"][tool] is None:
                                    agg["static_analysis_failures"][tool] = val_int
                                else:
                                    agg["static_analysis_failures"][tool] += val_int
                            except (TypeError, ValueError):
                                print(f"경고: {f} coder {coder_id} mvp.static_analysis_failures.{tool} 값 비정상 — 건너뜀", file=sys.stderr)
            if isinstance(review_outcome, dict):
                for key, target_key in [("must_fix_count", "must_fix_count"),
                                       ("good_to_fix_count", "good_to_fix_count"),
                                       ("refix_plans_written", "refix_plans_written")]:
                    val = review_outcome.get(key, 0)
                    try:
                        agg[target_key] += int(val) if val is not None else 0
                    except (TypeError, ValueError):
                        print(f"경고: {f} coder {coder_id} review_outcome.{key} 값 비정상 — 0으로 처리", file=sys.stderr)
    return stats


def _empty_coder_dict() -> dict:
    return {
        "issues": set(),
        "loc_added": 0,
        "static_analysis_failures": {"ruff": None, "pyright": None},
        "must_fix_count": 0,
        "good_to_fix_count": 0,
        "refix_plans_written": 0,
        "model": "",
    }


def promotion_rate(agg: dict[str, int]) -> float:
    if agg["findings"] <= 0:
        return 0.0
    return (agg["must_fix"] + agg["good_to_fix"]) / agg["findings"]


def render_table(
    stats: dict[str, dict[str, int]],
    cycles: int,
    coders: dict[str, dict] | None = None,
) -> str:
    rows = sorted(stats.items(), key=lambda kv: promotion_rate(kv[1]), reverse=True)
    header = (f"{'리뷰어':<12} {'사이클':>6} {'finding':>8} {'must':>5} {'good':>5} "
              f"{'gate-rej':>8} {'verify-rej':>10} {'승격률':>7}")
    lines: list[str] = [f"집계 사이클: {cycles}", header, "-" * len(header)]
    for name, agg in rows:
        lines.append(
            f"{name:<12} {agg['cycles']:>6} {agg['findings']:>8} {agg['must_fix']:>5} "
            f"{agg['good_to_fix']:>5} {agg['gate_rejected']:>8} {agg['verify_rejected']:>10} "
            f"{promotion_rate(agg) * 100:>6.1f}%"
        )
    lines.append("")
    lines.append("해석: 승격률이 지속적으로 낮은 리뷰어는 교체 후보 — 단 표본(사이클·finding)이 적으면 판단 유보.")
    if coders:
        lines.append("")
        lines.append("=== coder 섹션 ===")
        coder_rows = sorted(
            coders.items(),
            key=lambda kv: (
                (
                    ((kv[1]["static_analysis_failures"]["ruff"] or 0) +
                     (kv[1]["static_analysis_failures"]["pyright"] or 0) +
                     kv[1]["must_fix_count"]) / kv[1]["loc_added"] * 1000
                ) if kv[1]["loc_added"] > 0 else 0.0
            ),
            reverse=True,
        )
        coder_header = (
            f"{'coder':<12} {'이슈':>5} {'loc_added':>10} "
            f"{'ruff':>6} {'pyright':>8} {'must':>5} {'good':>5} {'refix':>6} "
            f"{'density':>8} {'static':>7} {'review':>7}"
        )
        lines.append(coder_header)
        lines.append("-" * len(coder_header))
        for name, agg in coder_rows:
            loc = agg["loc_added"]
            ruff = agg["static_analysis_failures"]["ruff"]
            pyright = agg["static_analysis_failures"]["pyright"]
            static_fail_sum = (ruff or 0) + (pyright or 0)
            must_fix = agg["must_fix_count"]
            good = agg["good_to_fix_count"]
            refix = agg["refix_plans_written"]
            density = (static_fail_sum + must_fix) / loc * 1000 if loc > 0 else 0.0
            static_density = static_fail_sum / loc * 1000 if loc > 0 else 0.0
            review_density = must_fix / loc * 1000 if loc > 0 else 0.0
            ruff_str = str(ruff) if ruff is not None else "-"
            pyright_str = str(pyright) if pyright is not None else "-"
            lines.append(
                f"{name:<12} {len(agg['issues']):>5} {loc:>10} "
                f"{ruff_str:>6} {pyright_str:>8} {must_fix:>5} {good:>5} {refix:>6} "
                f"{density:>8.1f} {static_density:>7.1f} {review_density:>7.1f}"
            )
        lines.append("")
        lines.append("해석: density가 지속적으로 높은 coder는 기초 코딩 및 리뷰 점검 후보.")
    return "\n".join(lines)


def render_json(
    stats: dict[str, dict[str, int]],
    cycles: int,
    coders: dict[str, dict],
) -> dict:
    reviewers_out = {
        name: {**agg, "promotion_rate": promotion_rate(agg)}
        for name, agg in stats.items()
    }
    coders_out: dict[str, dict] = {}
    for name, agg in coders.items():
        loc = agg["loc_added"]
        ruff = agg["static_analysis_failures"]["ruff"]
        pyright = agg["static_analysis_failures"]["pyright"]
        static_fail_sum = (ruff or 0) + (pyright or 0)
        must_fix = agg["must_fix_count"]
        density = (static_fail_sum + must_fix) / loc * 1000 if loc > 0 else 0.0
        static_density = static_fail_sum / loc * 1000 if loc > 0 else 0.0
        review_density = must_fix / loc * 1000 if loc > 0 else 0.0
        coders_out[name] = {
            "issues": sorted(agg["issues"]),
            "loc_added": loc,
            "static_analysis_failures": agg["static_analysis_failures"],
            "must_fix_count": must_fix,
            "good_to_fix_count": agg["good_to_fix_count"],
            "refix_plans_written": agg["refix_plans_written"],
            "model": agg["model"],
            "defect_density_per_kloc": round(density, 1),
            "static_density_per_kloc": round(static_density, 1),
            "review_density_per_kloc": round(review_density, 1),
        }
    return {
        "cycles": cycles,
        "reviewers": reviewers_out,
        "coders": coders_out,
    }


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    repo = Path(args.repo).resolve()
    issues_dir = repo / "issues"
    if not issues_dir.is_dir():
        print(f"ERROR: {issues_dir} 디렉토리가 없습니다 — 대상 리포가 맞습니까?", file=sys.stderr)
        return 1

    stats, cycles = collect(repo, args.since)
    coders = collect_coders(repo, args.since)

    has_reviewers = bool(stats)
    has_coders = bool(coders)

    if args.as_json:
        payload = render_json(stats, cycles, coders)
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    if not has_reviewers and not has_coders:
        print("집계할 review-stats/coder-stats JSON 또는 JSONL이 없습니다.")
        return 0

    print(render_table(stats, cycles, coders))
    return 0


if __name__ == "__main__":
    sys.exit(main())
