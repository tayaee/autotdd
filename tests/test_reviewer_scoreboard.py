"""tools/reviewer-scoreboard.py 단위 테스트 (issue-43, issue-47에서 agent-stats.json으로 이관).

공개 경계(CLI 프로세스)에서 검증한다 — 내부 함수가 아니라 실제 실행
결과(stdout/stderr/exit code)를 단언한다.
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


def write_stats(issues_dir: Path, n: int, started: str, reviewers: dict) -> None:
    issues_dir.mkdir(parents=True, exist_ok=True)
    # 실제 파이프라인에서는 tdd2가 coders 골격을 먼저 만들어 두므로
    # reviewers만 있는 픽스처도 coders: {}를 함께 둔다(현실적 형태 유지).
    payload = {"issue": n, "started": started, "reviewers": reviewers,
               "derived_by_reviewers": [], "coders": {}}
    (issues_dir / f"issue-{n}__TYPE-agent-stats.json").write_text(
        json.dumps(payload), encoding="utf-8"
    )


def make_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    (repo / "issues").mkdir(parents=True)
    return repo


def test_aggregates_two_cycles_across_live_and_archive(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    write_stats(repo / "issues", 21, "2026-07-01T10:00:00", {
        "qwen": {"findings": 10, "gate_rejected": 4, "verify_rejected": 1,
                 "must_fix": 2, "good_to_fix": 3},
    })
    write_stats(repo / "issues" / "archive" / "2026" / "07" / "02", 22,
                "2026-07-02T10:00:00", {
        "qwen": {"findings": 6, "gate_rejected": 1, "verify_rejected": 0,
                 "must_fix": 2, "good_to_fix": 1},
        "minimax": {"findings": 4, "gate_rejected": 0, "verify_rejected": 0,
                    "must_fix": 3, "good_to_fix": 1},
    })
    proc = run_cli(str(repo))
    assert proc.returncode == 0
    assert "qwen" in proc.stdout and "minimax" in proc.stdout
    # qwen: (2+3+2+1)/16 = 50.0% / minimax: 4/4 = 100.0%
    assert "50.0%" in proc.stdout
    assert "100.0%" in proc.stdout
    # 해석 가이드
    assert "교체 후보" in proc.stdout


def test_json_output_is_machine_readable(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    write_stats(repo / "issues", 21, "2026-07-01T10:00:00", {
        "qwen": {"findings": 10, "gate_rejected": 4, "verify_rejected": 1,
                 "must_fix": 2, "good_to_fix": 3},
    })
    proc = run_cli(str(repo), "--json")
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    q = data["reviewers"]["qwen"]
    assert q["findings"] == 10
    assert q["must_fix"] == 2
    assert q["promotion_rate"] == 0.5


def test_since_filters_older_cycles(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    write_stats(repo / "issues", 21, "2026-06-01T10:00:00", {
        "qwen": {"findings": 5, "gate_rejected": 0, "verify_rejected": 0,
                 "must_fix": 5, "good_to_fix": 0},
    })
    write_stats(repo / "issues", 22, "2026-07-05T10:00:00", {
        "qwen": {"findings": 2, "gate_rejected": 0, "verify_rejected": 0,
                 "must_fix": 1, "good_to_fix": 0},
    })
    proc = run_cli(str(repo), "--since", "2026-07-01", "--json")
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    assert data["cycles"] == 1
    assert data["reviewers"]["qwen"]["findings"] == 2


def test_corrupt_json_warns_and_continues(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    write_stats(repo / "issues", 21, "2026-07-01T10:00:00", {
        "qwen": {"findings": 3, "gate_rejected": 0, "verify_rejected": 0,
                 "must_fix": 1, "good_to_fix": 1},
    })
    (repo / "issues" / "issue-9__TYPE-agent-stats.json").write_text(
        "{not valid json", encoding="utf-8"
    )
    proc = run_cli(str(repo))
    assert proc.returncode == 0          # 손상 파일이 실행을 죽이지 않음
    assert "issue-9" in proc.stderr      # 침묵 금지 — 경고 출력
    assert "qwen" in proc.stdout         # 생존 파일은 정상 집계


def test_coder_only_file_without_reviewers_is_not_corruption(tmp_path: Path) -> None:
    """리뷰 사이클 없이 순수 /tdd2 + /acpd만 거친 이슈는 reviewers 키 자체가 없다.

    이는 손상이 아니라 정상 상태(issue-47) — 경고 없이 조용히 리뷰어
    집계에서만 제외되어야 한다(coders 집계에는 영향 없음, 그건
    collect_coders의 몫).
    """
    repo = make_repo(tmp_path)
    (repo / "issues").mkdir(parents=True, exist_ok=True)
    (repo / "issues" / "issue-30__TYPE-agent-stats.json").write_text(
        json.dumps({"issue": 30, "started": "2026-07-01T10:00:00Z",
                    "coders": {"sonnet5": {"model": "Claude Sonnet 5"}}}),
        encoding="utf-8",
    )
    write_stats(repo / "issues", 21, "2026-07-01T10:00:00", {
        "qwen": {"findings": 3, "gate_rejected": 0, "verify_rejected": 0,
                 "must_fix": 1, "good_to_fix": 1},
    })
    proc = run_cli(str(repo))
    assert proc.returncode == 0
    assert "issue-30" not in proc.stderr
    assert proc.stderr.strip() == ""
    assert "qwen" in proc.stdout


def test_empty_issues_dir_reports_no_data(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    proc = run_cli(str(repo))
    assert proc.returncode == 0
    assert "없" in proc.stdout           # "집계할 데이터가 없습니다" 류


def test_missing_issues_dir_fails_loudly(tmp_path: Path) -> None:
    repo = tmp_path / "not-a-target"
    repo.mkdir()
    proc = run_cli(str(repo))
    assert proc.returncode == 1
    assert proc.stderr.strip() != ""


def test_model_field_does_not_affect_aggregation(tmp_path: Path) -> None:
    """issue-44: reviewer 항목의 `model` 필드는 집계에 영향 없음.

    스코어보드는 COUNT_KEYS만 합산하므로 미지 필드(model)는 자동으로
    무시되어야 한다 — 래퍼 버전이 바뀌어도 누적 데이터가 섞이지 않게
    보존되는 동작이다. 이 테스트는 그 계약을 고정한다.
    """
    repo = make_repo(tmp_path)
    write_stats(repo / "issues", 21, "2026-07-01T10:00:00", {
        "qwen": {
            "model": "qwen 3 max preview",
            "findings": 10, "gate_rejected": 4, "verify_rejected": 1,
            "must_fix": 2, "good_to_fix": 3,
        },
    })
    proc = run_cli(str(repo), "--json")
    assert proc.returncode == 0
    data = json.loads(proc.stdout)
    q = data["reviewers"]["qwen"]
    assert q["findings"] == 10
    assert q["must_fix"] == 2
    assert q["good_to_fix"] == 3
    assert q["promotion_rate"] == 0.5


def test_model_field_table_output_matches_without_model(tmp_path: Path) -> None:
    """issue-44: model 필드 있어도 테이블 출력은 동일해야 한다."""
    repo_a = make_repo(tmp_path / "a")
    repo_b = make_repo(tmp_path / "b")
    write_stats(repo_a / "issues", 21, "2026-07-01T10:00:00", {
        "qwen": {
            "model": "Qwen 3 Max",
            "findings": 10, "gate_rejected": 4, "verify_rejected": 1,
            "must_fix": 2, "good_to_fix": 3,
        },
    })
    write_stats(repo_b / "issues", 21, "2026-07-01T10:00:00", {
        "qwen": {
            "findings": 10, "gate_rejected": 4, "verify_rejected": 1,
            "must_fix": 2, "good_to_fix": 3,
        },
    })
    out_a = run_cli(str(repo_a)).stdout
    out_b = run_cli(str(repo_b)).stdout
    # 승격률·finding·must/good 등 숫자가 동일하면 통과 (헤더는 동일)
    assert "50.0%" in out_a and "50.0%" in out_b
    # 두 출력에서 모델명은 어디에도 나오면 안 됨 (집계 단위는 base명)
    assert "Qwen 3 Max" not in out_a
    assert "qwen 3 max" not in out_a.lower()
