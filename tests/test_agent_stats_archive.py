"""tools/agent-stats-archive.py 단위 테스트 (issue-47).

공개 경계(CLI 프로세스)에서 검증한다 — reviewer-scoreboard.py 테스트와
동일 관례.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parent.parent
    / ".claude" / "skills" / "acpd" / "defaults" / "agent-stats-archive.py"
)

_DUR_RE = re.compile(r"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$")


def duration_to_seconds(value: str) -> int:
    """ISO 8601 duration 문자열을 초로 변환하는 독립 파서(구현과 별개 로직)."""
    m = _DUR_RE.match(value)
    assert m, f"invalid ISO8601 duration: {value!r}"
    days, hours, minutes, seconds = (int(g) if g else 0 for g in m.groups())
    return days * 86400 + hours * 3600 + minutes * 60 + seconds


def run_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True, text=True, timeout=30,
    )


def make_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    (repo / "issues").mkdir(parents=True)
    return repo


def write_stats(issues_dir: Path, n: int, data: dict, stream: str = "issue") -> Path:
    issues_dir.mkdir(parents=True, exist_ok=True)
    p = issues_dir / f"{stream}-{n}__agent-stats.json"
    p.write_text(json.dumps(data), encoding="utf-8")
    return p


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def test_fills_archived_and_duration_across_day_boundary(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    started = datetime.now(timezone.utc) - timedelta(hours=26, minutes=15)
    p = write_stats(repo / "issues", 46, {
        "issue": 46,
        "started": iso(started),
        "coders": {"sonnet5": {"model": "Claude Sonnet 5"}},
    })
    proc = run_cli(str(repo), "issue-46")
    assert proc.returncode == 0, proc.stderr

    data = json.loads(p.read_text(encoding="utf-8"))
    assert "archived" in data
    archived = datetime.fromisoformat(data["archived"].replace("Z", "+00:00"))
    actual_delta = (archived - started).total_seconds()
    assert actual_delta >= 0
    # 독립 파서로 되돌린 duration이 실제 경과 시간과 근접해야 함
    # (started를 초 단위로 직렬화하며 최대 1초 소실 + 실행 오버헤드 감안, 2초 허용)
    assert abs(actual_delta - duration_to_seconds(data["duration"])) < 2
    # 26시간 15분 경과 = 하루(1D) 경계를 넘음
    assert data["duration"].startswith("P1DT2H15M")


def test_fills_short_duration_without_day_component(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    started = datetime.now(timezone.utc) - timedelta(minutes=30)
    p = write_stats(repo / "issues", 47, {
        "issue": 47,
        "started": iso(started),
        "coders": {},
    })
    proc = run_cli(str(repo), "issue-47")
    assert proc.returncode == 0, proc.stderr

    data = json.loads(p.read_text(encoding="utf-8"))
    assert re.match(r"^PT30M\d*S?$", data["duration"]) or re.match(r"^PT30M$", data["duration"])
    assert "D" not in data["duration"]


def test_preserves_existing_reviewers_and_coders(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    started = datetime.now(timezone.utc) - timedelta(hours=1)
    payload = {
        "issue": 48,
        "started": iso(started),
        "reviewers": {"qwen": {"model": "Qwen 3", "findings": 2, "must_fix": 1,
                                "good_to_fix": 1, "gate_rejected": 0, "verify_rejected": 0}},
        "derived_by_reviewers": ["issue-49-fixing-48.md"],
        "coders": {"sonnet5": {"model": "Claude Sonnet 5",
                                "mvp": {"ts": iso(started), "loc_added": 50,
                                        "static_analysis_failures": {"ruff": 0, "pyright": 0}}}},
    }
    p = write_stats(repo / "issues", 48, payload)
    proc = run_cli(str(repo), "issue-48")
    assert proc.returncode == 0, proc.stderr

    data = json.loads(p.read_text(encoding="utf-8"))
    assert data["reviewers"] == payload["reviewers"]
    assert data["derived_by_reviewers"] == payload["derived_by_reviewers"]
    assert data["coders"] == payload["coders"]
    assert data["issue"] == 48


def test_missing_started_field_errors_and_leaves_file_untouched(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    p = write_stats(repo / "issues", 46, {"issue": 46, "coders": {}})
    before = p.read_text(encoding="utf-8")
    proc = run_cli(str(repo), "issue-46")
    assert proc.returncode != 0
    assert "started" in proc.stderr
    assert p.read_text(encoding="utf-8") == before


def test_missing_stats_file_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    proc = run_cli(str(repo), "issue-99")
    assert proc.returncode != 0
    assert proc.stderr.strip() != ""


def test_invalid_stream_id_errors(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    proc = run_cli(str(repo), "not-a-valid-id")
    assert proc.returncode != 0
    assert proc.stderr.strip() != ""


def test_autofix_stream_supported(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    started = datetime.now(timezone.utc) - timedelta(minutes=5)
    p = write_stats(repo / "issues", 3, {
        "issue": 3, "started": iso(started), "coders": {},
    }, stream="autofix")
    proc = run_cli(str(repo), "autofix-3")
    assert proc.returncode == 0, proc.stderr
    data = json.loads(p.read_text(encoding="utf-8"))
    assert "archived" in data
    assert "duration" in data
