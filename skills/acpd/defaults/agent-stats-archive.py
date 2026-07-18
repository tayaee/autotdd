#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""agent-stats-archive — issue-N__agent-stats.json에 archived/duration을 채운다 (issue-47, v3 마커 개명).

acpd(aacp.sh/.ps1)가 이 이슈의 산출물(code-review/refix-plan/agent-stats)을
아카이브 디렉터리로 git mv하기 직전, agent-stats.json에 한해 이 스크립트를 먼저 호출한다.
기존 `started` 필드를 기준으로 `archived`(현재 로컬 타임존 오프셋 포함
ISO 8601, 예: `2026-07-13T14:23:01-04:00` — UTC `Z` 아님)와
`duration`(ISO 8601 duration, archived - started)을 계산해 같은 파일에
덮어쓴다. 표준 라이브러리만 사용.

사용법:
    agent-stats-archive.py <repo-path> <issue-N|autofix-N>
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

STREAM_RE = re.compile(r"^(issue|autofix)-([0-9]+)$")


def parse_stream_id(value: str) -> tuple[str, str]:
    m = STREAM_RE.match(value)
    if not m:
        raise ValueError(f"스트림 ID 형식이 아님: {value!r} (issue-N 또는 autofix-N)")
    return m.group(1), m.group(2)


def find_stats_file(repo: Path, stream: str, n: str) -> Path:
    path = repo / "issues" / f"{stream}-{n}__agent-stats.json"
    if not path.is_file():
        raise FileNotFoundError(f"{path} 없음")
    return path


def parse_iso8601(value: str) -> datetime:
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def format_iso8601(dt: datetime) -> str:
    """로컬 타임존 오프셋을 포함한 ISO 8601 문자열로 (예: -04:00). UTC로 강제하지 않는다."""
    return dt.astimezone().isoformat(timespec="seconds")


def format_duration(total_seconds: int) -> str:
    """정수 초를 ISO 8601 duration으로. 날짜 경계를 넘으면 D 성분을 쓴다(비정규화 H 누적 안 함)."""
    if total_seconds < 0:
        raise ValueError(f"archived가 started보다 이전임 (음수 기간: {total_seconds}s)")
    days, rem = divmod(total_seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, seconds = divmod(rem, 60)
    date_part = f"{days}D" if days else ""
    time_units = []
    if hours:
        time_units.append(f"{hours}H")
    if minutes:
        time_units.append(f"{minutes}M")
    if seconds or not (days or hours or minutes):
        time_units.append(f"{seconds}S")
    time_part = "T" + "".join(time_units) if time_units else ""
    return f"P{date_part}{time_part}"


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 2:
        print("Usage: agent-stats-archive.py <repo-path> <issue-N|autofix-N>", file=sys.stderr)
        return 1

    repo = Path(args[0]).resolve()
    try:
        stream, n = parse_stream_id(args[1])
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    try:
        path = find_stats_file(repo, stream, n)
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"ERROR: {path} 파싱 불가 ({exc})", file=sys.stderr)
        return 1

    if not isinstance(data, dict):
        print(f"ERROR: {path} 객체 아님", file=sys.stderr)
        return 1

    started_raw = data.get("started")
    if not isinstance(started_raw, str):
        print(f"ERROR: {path}에 started 필드가 없음", file=sys.stderr)
        return 1

    try:
        started = parse_iso8601(started_raw)
    except ValueError as exc:
        print(f"ERROR: {path}의 started 값 파싱 불가 ({exc})", file=sys.stderr)
        return 1

    archived = datetime.now().astimezone()
    delta_seconds = int(round((archived - started).total_seconds()))
    try:
        duration = format_duration(delta_seconds)
    except ValueError as exc:
        print(f"ERROR: {path} — {exc}", file=sys.stderr)
        return 1

    data["archived"] = format_iso8601(archived)
    data["duration"] = duration
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{path}: archived={data['archived']} duration={duration}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
