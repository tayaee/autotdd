"""tools/reviewer-scoreboard.py coder 섹션 단위 테스트 (issue-45).

리뷰어와 동일한 CLI 진입점에서 coder-stats JSONL도 함께 집계한다.
공개 경계(CLI 프로세스)에서 검증한다.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "tools" / "reviewer-scoreboard.py"


def run_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True, text=True, timeout=30,
    )


def make_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    (repo / "issues").mkdir(parents=True)
    return repo


def write_coder_jsonl(issues_dir: Path, n: int, lines: list[dict]) -> None:
    issues_dir.mkdir(parents=True, exist_ok=True)
    p = issues_dir / f"issue-{n}__TYPE-coder-stats.jsonl"
    with p.open("w", encoding="utf-8") as f:
        for line in lines:
            f.write(json.dumps(line, ensure_ascii=False) + "\n")


def test_coder_section_aggregates_per_model(tmp_path: Path) -> None:
    """같은 이슈에서 여러 run이 모여도 coder(model)별로 합산된다."""
    repo = make_repo(tmp_path)
    write_coder_jsonl(repo / "issues", 21, [
        {"kind": "run", "ts": "2026-07-01T10:00:00", "tool": "ruff",
         "exit": 1, "errors": 5, "fixed": 2, "syntax_errors": 0},
        {"kind": "run", "ts": "2026-07-01T10:01:00", "tool": "pyright",
         "exit": 1, "errors": 3, "fixed": 0, "syntax_errors": 0},
        {"kind": "summary", "ts": "2026-07-01T10:02:00",
         "coder": "sonnet", "model": "Claude Sonnet 4.6",
         "loc_added": 200},
    ])
    write_coder_jsonl(repo / "issues" / "archive" / "2026" / "07" / "02", 22, [
        {"kind": "summary", "ts": "2026-07-02T11:00:00",
         "coder": "minimax", "model": "MiniMax-M3",
         "loc_added": 500},
        {"kind": "run", "ts": "2026-07-02T11:01:00", "tool": "ruff",
         "exit": 0, "errors": 0, "fixed": 0, "syntax_errors": 0},
    ])

    proc = run_cli(str(repo), "--json")
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert "coders" in data
    coders = data["coders"]

    # sonnet: errors=5+3=8, fixed=2+0=2, syntax=0, loc=200, density=(8+2)/200*1000=50.0
    assert coders["sonnet"]["errors"] == 8
    assert coders["sonnet"]["fixed"] == 2
    assert coders["sonnet"]["syntax_errors"] == 0
    assert coders["sonnet"]["loc_added"] == 200
    assert coders["sonnet"]["runs"] == 2
    assert coders["sonnet"]["defect_density_per_kloc"] == 50.0

    # minimax: loc=500, density=0
    assert coders["minimax"]["loc_added"] == 500
    assert coders["minimax"]["defect_density_per_kloc"] == 0.0
    assert coders["minimax"]["runs"] == 1


def test_coder_defect_density_is_per_kloc(tmp_path: Path) -> None:
    """defect 밀도는 1000라인당으로 표시 (issue-45 spec)."""
    repo = make_repo(tmp_path)
    # errors+fixed=12 over 60 lines = 200 per kloc
    write_coder_jsonl(repo / "issues", 21, [
        {"kind": "summary", "ts": "2026-07-01T10:00:00",
         "coder": "qwen", "model": "qwen 3 max",
         "loc_added": 60},
        {"kind": "run", "ts": "2026-07-01T10:01:00", "tool": "ruff",
         "exit": 1, "errors": 10, "fixed": 2, "syntax_errors": 0},
    ])
    proc = run_cli(str(repo), "--json")
    data = json.loads(proc.stdout)
    assert data["coders"]["qwen"]["defect_density_per_kloc"] == 200.0


def test_coder_syntax_errors_separate_column(tmp_path: Path) -> None:
    """syntax_errors는 일반 errors와 별도 컬럼(기초 실수 지표)."""
    repo = make_repo(tmp_path)
    write_coder_jsonl(repo / "issues", 21, [
        {"kind": "summary", "ts": "2026-07-01T10:00:00",
         "coder": "deepseek", "model": "deepseek-v3",
         "loc_added": 100},
        {"kind": "run", "ts": "2026-07-01T10:01:00", "tool": "ruff",
         "exit": 1, "errors": 4, "fixed": 0, "syntax_errors": 2},
    ])
    proc = run_cli(str(repo))
    # stderr/stdout 상관없이 키 자체는 JSON에 노출
    jproc = run_cli(str(repo), "--json")
    data = json.loads(jproc.stdout)
    assert data["coders"]["deepseek"]["errors"] == 4
    assert data["coders"]["deepseek"]["syntax_errors"] == 2
    # 기초 실수(E999)는 defect 밀도에 합산하지 않음
    assert data["coders"]["deepseek"]["defect_density_per_kloc"] == 40.0  # (4+0)/100*1000


def test_coder_section_runs_increment_per_run_line(tmp_path: Path) -> None:
    """run 횟수는 kind=run 라인 수 (churn 신호)."""
    repo = make_repo(tmp_path)
    write_coder_jsonl(repo / "issues", 21, [
        {"kind": "run", "ts": "2026-07-01T10:00:00", "tool": "ruff",
         "exit": 1, "errors": 1, "fixed": 0, "syntax_errors": 0},
        {"kind": "run", "ts": "2026-07-01T10:01:00", "tool": "pyright",
         "exit": 1, "errors": 1, "fixed": 0, "syntax_errors": 0},
        {"kind": "run", "ts": "2026-07-01T10:02:00", "tool": "ruff",
         "exit": 1, "errors": 1, "fixed": 0, "syntax_errors": 0},
        {"kind": "summary", "ts": "2026-07-01T10:03:00",
         "coder": "sonnet", "model": "Claude Sonnet 4.6",
         "loc_added": 30},
    ])
    proc = run_cli(str(repo), "--json")
    data = json.loads(proc.stdout)
    assert data["coders"]["sonnet"]["runs"] == 3
    # errors는 run 라인에서만 합산
    assert data["coders"]["sonnet"]["errors"] == 3


def test_coder_since_filter(tmp_path: Path) -> None:
    """--since 필터는 issue의 latest summary ts를 기준으로."""
    repo = make_repo(tmp_path)
    write_coder_jsonl(repo / "issues", 21, [
        {"kind": "summary", "ts": "2026-06-01T10:00:00",
         "coder": "old", "model": "old-1.0", "loc_added": 100},
        {"kind": "run", "ts": "2026-06-01T10:01:00", "tool": "ruff",
         "exit": 1, "errors": 5, "fixed": 0, "syntax_errors": 0},
    ])
    write_coder_jsonl(repo / "issues", 22, [
        {"kind": "summary", "ts": "2026-07-05T10:00:00",
         "coder": "sonnet", "model": "Claude Sonnet 4.6", "loc_added": 200},
        {"kind": "run", "ts": "2026-07-05T10:01:00", "tool": "ruff",
         "exit": 1, "errors": 1, "fixed": 0, "syntax_errors": 0},
    ])
    proc = run_cli(str(repo), "--since", "2026-07-01", "--json")
    data = json.loads(proc.stdout)
    assert "sonnet" in data["coders"]
    assert "old" not in data["coders"]


def test_coder_corrupt_line_warns_and_continues(tmp_path: Path) -> None:
    """손상 라인은 stderr 경고 + 나머지 라인은 정상 집계 (침묵 금지).

    두 개의 파일(서로 다른 이슈)에 손상 라인을 뿌려 한쪽 손상이 다른쪽을
    망치지 않음을 보여준다.
    """
    repo = make_repo(tmp_path)
    issues_dir = repo / "issues"
    issues_dir.mkdir(parents=True, exist_ok=True)

    p1 = issues_dir / "issue-21__TYPE-coder-stats.jsonl"
    p1.write_text(
        '{"kind":"summary","ts":"2026-07-01T10:00:00","coder":"sonnet","model":"x","loc_added":100}\n'
        + '{"kind":"run","ts":"2026-07-01T10:01:00","tool":"ruff","exit":1,"errors":2,"fixed":0,"syntax_errors":0}\n'
        + "{not valid json\n",
        encoding="utf-8",
    )
    p2 = issues_dir / "issue-22__TYPE-coder-stats.jsonl"
    p2.write_text(
        '{"kind":"summary","ts":"2026-07-02T10:00:00","coder":"minimax","model":"y","loc_added":50}\n',
        encoding="utf-8",
    )

    proc = run_cli(str(repo))
    assert proc.returncode == 0
    assert "issue-21" in proc.stderr
    jproc = run_cli(str(repo), "--json")
    data = json.loads(jproc.stdout)
    # 손상 라인이 있는 파일의 정상 라인 + 손상 없는 파일 둘 다 살아있어야 함
    assert data["coders"]["sonnet"]["errors"] == 2
    assert data["coders"]["minimax"]["loc_added"] == 50


def test_coder_section_handles_orphan_run_without_summary(tmp_path: Path) -> None:
    """summary 없는 run-only JSONL: loc_added=0, runs 카운트, errors 합산."""
    repo = make_repo(tmp_path)
    write_coder_jsonl(repo / "issues", 21, [
        {"kind": "run", "ts": "2026-07-01T10:00:00", "tool": "ruff",
         "exit": 1, "errors": 3, "fixed": 0, "syntax_errors": 0},
    ])
    proc = run_cli(str(repo), "--json")
    data = json.loads(proc.stdout)
    # coder 식별 불가(고아 run) → 분류키 없음, 카테고리만 집계
    assert "orphan_runs" in data["coders"]
    assert data["coders"]["orphan_runs"]["errors"] == 3
    assert data["coders"]["orphan_runs"]["loc_added"] == 0
    # loc_added=0 → 밀도 0.0
    assert data["coders"]["orphan_runs"]["defect_density_per_kloc"] == 0.0


def test_coder_summary_must_have_coder_field(tmp_path: Path) -> None:
    """summary 라인은 `coder` 필드 필수 — 없으면 침묵 거부."""
    repo = make_repo(tmp_path)
    write_coder_jsonl(repo / "issues", 21, [
        {"kind": "summary", "ts": "2026-07-01T10:00:00",
         "model": "no-coder-field", "loc_added": 100},
    ])
    proc = run_cli(str(repo))
    assert proc.returncode == 0
    # 모델 누락 summary는 경고 후 합산 제외
    assert "model" in proc.stderr or "coder" in proc.stderr


def test_coder_multiple_summaries_per_coder_accumulate(tmp_path: Path) -> None:
    """같은 coder가 여러 이슈에서 run/summary를 누적 (집계의 핵심)."""
    repo = make_repo(tmp_path)
    write_coder_jsonl(repo / "issues", 21, [
        {"kind": "summary", "ts": "2026-07-01T10:00:00",
         "coder": "sonnet", "model": "Claude Sonnet 4.6", "loc_added": 100},
        {"kind": "run", "ts": "2026-07-01T10:01:00", "tool": "ruff",
         "exit": 1, "errors": 2, "fixed": 0, "syntax_errors": 0},
    ])
    write_coder_jsonl(repo / "issues", 22, [
        {"kind": "summary", "ts": "2026-07-02T10:00:00",
         "coder": "sonnet", "model": "Claude Sonnet 4.6", "loc_added": 150},
        {"kind": "run", "ts": "2026-07-02T10:01:00", "tool": "ruff",
         "exit": 1, "errors": 3, "fixed": 1, "syntax_errors": 0},
    ])
    proc = run_cli(str(repo), "--json")
    data = json.loads(proc.stdout)
    sonnet = data["coders"]["sonnet"]
    assert sonnet["errors"] == 5       # 2+3
    assert sonnet["fixed"] == 1
    assert sonnet["loc_added"] == 250  # 100+150
    assert sonnet["runs"] == 2         # 2개 run 라인
    # density = (5+1)/250 * 1000 = 24.0
    assert sonnet["defect_density_per_kloc"] == 24.0
