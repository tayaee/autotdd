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
    """구현자 coder-stats JSONL을 재귀 수집·집계.

    한 파일 = 한 이슈. summary 라인의 `coder` 필드가 그 파일 전체의
    coder 식별자이며, 같은 파일의 run 라인들은 그 식별자로 귀속된다.
    summary가 없는 파일의 run들은 `orphan_runs` 키로 묶음.

    손상 라인/누락 필드는 stderr 경고 후 계속(침묵 금지).
    """
    issues_dir = repo / "issues"
    stats: dict[str, dict] = {}
    for f in sorted(issues_dir.rglob("*__TYPE-coder-stats.jsonl")):
        # 파일명에서 이슈 번호 추출 — `issue-N__TYPE-coder-stats.jsonl`
        # 패턴에서 첫 `issue-` 직후의 정수만 가져온다.
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
        issue_n: int = int(digits)
        try:
            text = f.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"경고: {f} 읽기 실패 — 건너뜀 ({exc})", file=sys.stderr)
            continue

        # 1차 패스: 라인 파싱 + 파일 coder 식별 + ts 필터
        run_objs: list[dict] = []
        summary_objs: list[dict] = []
        file_coder: str | None = None
        any_summary_seen = False
        any_summary_kept = False
        for lineno, line in enumerate(text.splitlines(), 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as exc:
                print(f"경고: {f}:{lineno} JSON 파싱 실패 — 건너뜀 ({exc})",
                      file=sys.stderr)
                continue
            if not isinstance(obj, dict):
                print(f"경고: {f}:{lineno} 객체 아님 — 건너뜀", file=sys.stderr)
                continue
            when = _parse_iso_date(obj.get("ts"))
            if since is not None and when is not None and when < since:
                continue
            kind = obj.get("kind")
            if kind == "summary":
                any_summary_seen = True
                coder_raw = obj.get("coder")
                if not isinstance(coder_raw, str) or not coder_raw:
                    print(f"경고: {f}:{lineno} summary에 coder 필드 없음 — 건너뜀",
                          file=sys.stderr)
                    continue
                file_coder = coder_raw
                any_summary_kept = True
                summary_objs.append(obj)
            elif kind == "run":
                run_objs.append(obj)
            else:
                print(f"경고: {f}:{lineno} 알 수 없는 kind={kind!r} — 건너뜀",
                      file=sys.stderr)

        # 2차 패스: 집게 — summary coder가 있으면 그쪽으로, 없으면 orphan_runs
        target_coder = file_coder if any_summary_kept else "orphan_runs"
        agg = stats.setdefault(target_coder, _empty_coder_dict())
        if any_summary_seen and not any_summary_kept:
            # 파일에 summary는 있었지만 모두 무효 — coder 미확정. 경고만 이미 출력.
            pass
        for obj in run_objs:
            agg["runs"] += 1
            for k in ("errors", "fixed", "syntax_errors"):
                v = obj.get(k)
                try:
                    agg[k] += int(v) if v is not None else 0
                except (TypeError, ValueError):
                    print(f"경고: {f} run 라인의 {k} 비정상 — 0으로 처리",
                          file=sys.stderr)
            if isinstance(obj.get("model"), str) and not agg["model"]:
                agg["model"] = obj["model"]
        for obj in summary_objs:
            assert issue_n is not None  # 위에서 continue로 가드됨
            agg["issues"].add(issue_n)
            if isinstance(obj.get("model"), str) and not agg["model"]:
                agg["model"] = obj["model"]
            v = obj.get("loc_added")
            try:
                agg["loc_added"] += int(v) if v is not None else 0
            except (TypeError, ValueError):
                print(f"경고: {f} summary의 loc_added 비정상 — 0으로 처리",
                      file=sys.stderr)
    return stats


def _empty_coder_dict() -> dict:
    return {
        "issues": set(),
        "runs": 0,
        "errors": 0,
        "fixed": 0,
        "syntax_errors": 0,
        "loc_added": 0,
        "model": "",
    }


def promotion_rate(agg: dict[str, int]) -> float:
    if agg["findings"] <= 0:
        return 0.0
    return (agg["must_fix"] + agg["good_to_fix"]) / agg["findings"]


def defect_density_per_kloc(agg: dict) -> float:
    """defect 밀도 = (errors + fixed) / loc_added * 1000. 0라인 가드."""
    loc = agg.get("loc_added", 0)
    if loc <= 0:
        return 0.0
    return (agg.get("errors", 0) + agg.get("fixed", 0)) / loc * 1000


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
        lines.append("=== coder 섹션 (정적분석 ruff/pyright 결과) ===")
        coder_rows = sorted(
            coders.items(),
            key=lambda kv: defect_density_per_kloc(kv[1]),
            reverse=True,
        )
        coder_header = (f"{'coder':<12} {'이슈':>5} {'run':>5} {'loc_added':>10} "
                        f"{'errors':>7} {'fixed':>6} {'syntax':>7} "
                        f"{'defect/kloc':>12}")
        lines.append(coder_header)
        lines.append("-" * len(coder_header))
        for name, agg in coder_rows:
            lines.append(
                f"{name:<12} {len(agg['issues']):>5} {agg['runs']:>5} {agg['loc_added']:>10} "
                f"{agg['errors']:>7} {agg['fixed']:>6} {agg['syntax_errors']:>7} "
                f"{defect_density_per_kloc(agg):>12.1f}"
            )
        lines.append("")
        lines.append("해석: defect/kloc이 지속적으로 높은 coder는 기초 코딩 점검 후보.")
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
        coders_out[name] = {
            "issues": sorted(agg["issues"]),
            "runs": agg["runs"],
            "errors": agg["errors"],
            "fixed": agg["fixed"],
            "syntax_errors": agg["syntax_errors"],
            "loc_added": agg["loc_added"],
            "model": agg["model"],
            "defect_density_per_kloc": defect_density_per_kloc(agg),
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
