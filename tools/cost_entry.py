"""cost_entry — cost_details 항목 스키마(Pydantic)와 agent-stats.json append 공통 로직.

`tools/log-cost-<base>.py` 8개, `tools/log-cost-summary.py`가 공유하는
라이브러리 모듈. 단독 실행용이 아니라 import해서 쓴다 — 호출하는
스크립트의 PEP 723 인라인 의존성(`dependencies = ["pydantic"]`)이 제공하는
`uv run` 환경에서 실행되는 것을 전제로 한다.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from pydantic import BaseModel

STREAM_RE = re.compile(r"^(issue|autofix)-([0-9]+)$")


class CostDetailEntry(BaseModel):
    ts: str
    model: str
    five_hour_used_pct: float | None
    seven_day_used_pct: float | None
    description: str


def parse_stream_id(value: str) -> tuple[str, str]:
    m = STREAM_RE.match(value)
    if not m:
        raise ValueError(f"스트림 ID 형식이 아님: {value!r} (issue-N 또는 autofix-N)")
    return m.group(1), m.group(2)


def now_iso8601() -> str:
    """로컬 타임존 오프셋 포함 ISO 8601 — UTC `Z` 금지(agent-stats.json 전체 규약)."""
    return datetime.now().astimezone().isoformat(timespec="seconds")


def append_cost_detail(
    repo: Path,
    target: str,
    *,
    model: str,
    five_hour_used_pct: float | None,
    seven_day_used_pct: float | None,
    description: str,
    dryrun: bool = False,
) -> tuple[Path, CostDetailEntry]:
    """대상 이슈의 agent-stats.json cost_details에 이벤트를 append한다.

    dryrun=True면 실제 기록을 하지 않으므로 대상 파일이 존재할 필요조차
    없다 — 파일을 조회·읽기 전에 곧바로 (계산된 경로, entry)만 반환한다.
    used_pct 조회·entry 구성은 dryrun에서도 동일하게 수행해 무엇이
    기록됐을지 확인할 수 있게 한다.
    """
    entry = CostDetailEntry(
        ts=now_iso8601(),
        model=model,
        five_hour_used_pct=five_hour_used_pct,
        seven_day_used_pct=seven_day_used_pct,
        description=description,
    )

    stream, n = parse_stream_id(target)
    path = repo / "issues" / f"{stream}-{n}__agent-stats.json"

    if dryrun:
        return path, entry

    if not path.is_file():
        raise FileNotFoundError(f"{path} 없음")

    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path} 객체 아님")

    data.setdefault("cost_details", []).append(entry.model_dump())
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    return path, entry


def _find_check_usage_js() -> Path | None:
    cache_root = Path.home() / ".claude/plugins/cache/claude-dashboard/claude-dashboard"
    if not cache_root.is_dir():
        return None
    versions = sorted(cache_root.glob("*/dist/check-usage.js"))
    return versions[-1] if versions else None


def query_check_usage_pct(provider_key: str) -> tuple[float | None, float | None]:
    """claude-dashboard의 check-usage.js --json을 호출해 provider_key(claude/gemini/codex/zai)의
    fiveHourPercent/sevenDayPercent를 얻는다.

    조회 불가능한 모든 경우(플러그인 미설치, node 실패, provider 미설치/에러)에
    (None, None)을 반환한다 — 침묵하지 않고 사유를 stderr에 남긴다.
    """
    script = _find_check_usage_js()
    if script is None:
        print("WARN: claude-dashboard check-usage.js 없음 — used_pct 조회 불가", file=sys.stderr)
        return None, None
    try:
        result = subprocess.run(
            ["node", str(script), "--json"],
            capture_output=True, text=True, timeout=15, check=True,
        )
        payload = json.loads(result.stdout)
    except Exception as exc:
        print(f"WARN: check-usage 조회 실패 ({exc}) — used_pct 조회 불가", file=sys.stderr)
        return None, None

    entry = payload.get(provider_key)
    if not entry or not entry.get("available") or entry.get("error"):
        print(f"WARN: check-usage의 {provider_key!r} provider 사용 불가 — used_pct null 기록", file=sys.stderr)
        return None, None
    return entry.get("fiveHourPercent"), entry.get("sevenDayPercent")
