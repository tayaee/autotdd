"""tools/reviewer-scoreboard.py coder 섹션 단위 테스트 (issue-46).
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


def write_coding_stats(issues_dir: Path, n: int, data: dict) -> None:
    issues_dir.mkdir(parents=True, exist_ok=True)
    p = issues_dir / f"issue-{n}__TYPE-coding-stats.json"
    with p.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def test_coder_section_aggregates_per_model(tmp_path: Path) -> None:
    """같은 coder가 여러 이슈에서 데이터를 누적하여 집계한다."""
    repo = make_repo(tmp_path)
    
    # issue-46: ruff=2, pyright=1, must_fix=1, good_to_fix=3, refix_plans=1, loc=192
    write_coding_stats(repo / "issues", 46, {
        "issue": 46,
        "coders": {
            "sonnet5": {
                "model": "Claude Sonnet 5",
                "mvp": {
                    "ts": "2026-07-13T01:30:50Z",
                    "loc_added": 192,
                    "static_analysis_failures": {"ruff": 2, "pyright": 1}
                },
                "review_outcome": {
                    "ts": "2026-07-12T21:40:00Z",
                    "findings_received": 4,
                    "must_fix_count": 1,
                    "good_to_fix_count": 3,
                    "refix_plans_written": 1
                }
            }
        }
    })

    # issue-47: ruff=0, pyright=0, must_fix=0, good_to_fix=1, refix_plans=0, loc=108
    write_coding_stats(repo / "issues", 47, {
        "issue": 47,
        "coders": {
            "sonnet5": {
                "model": "Claude Sonnet 5",
                "mvp": {
                    "ts": "2026-07-14T01:30:50Z",
                    "loc_added": 108,
                    "static_analysis_failures": {"ruff": 0, "pyright": 0}
                },
                "review_outcome": {
                    "ts": "2026-07-14T21:40:00Z",
                    "findings_received": 1,
                    "must_fix_count": 0,
                    "good_to_fix_count": 1,
                    "refix_plans_written": 0
                }
            }
        }
    })

    proc = run_cli(str(repo), "--json")
    assert proc.returncode == 0
    res = json.loads(proc.stdout)
    assert "coders" in res
    sonnet = res["coders"]["sonnet5"]
    
    assert sonnet["model"] == "Claude Sonnet 5"
    assert sonnet["issues"] == [46, 47]
    assert sonnet["loc_added"] == 300
    assert sonnet["static_analysis_failures"] == {"ruff": 2, "pyright": 1}
    assert sonnet["must_fix_count"] == 1
    assert sonnet["good_to_fix_count"] == 4
    assert sonnet["refix_plans_written"] == 1
    
    # Total defect density = (static_failures [3] + must_fix [1]) / 300 * 1000 = 13.333... -> 13.3
    assert abs(sonnet["defect_density_per_kloc"] - 13.3) < 0.1
    # Static component = 3 / 300 * 1000 = 10.0
    assert abs(sonnet["static_density_per_kloc"] - 10.0) < 0.1
    # Review component = 1 / 300 * 1000 = 3.333... -> 3.3
    assert abs(sonnet["review_density_per_kloc"] - 3.3) < 0.1


def test_coder_section_handles_null_static_failures(tmp_path: Path) -> None:
    """static_analysis_failures가 null인 경우(실행 안 됨) 집계 및 밀도 계산 검증."""
    repo = make_repo(tmp_path)
    
    write_coding_stats(repo / "issues", 48, {
        "issue": 48,
        "coders": {
            "qwen": {
                "model": "Qwen 2.5",
                "mvp": {
                    "ts": "2026-07-15T12:00:00Z",
                    "loc_added": 100,
                    "static_analysis_failures": {"ruff": None, "pyright": None}
                },
                "review_outcome": {
                    "ts": "2026-07-15T15:00:00Z",
                    "findings_received": 0,
                    "must_fix_count": 0,
                    "good_to_fix_count": 0,
                    "refix_plans_written": 0
                }
            }
        }
    })

    proc = run_cli(str(repo), "--json")
    assert proc.returncode == 0
    res = json.loads(proc.stdout)
    qwen = res["coders"]["qwen"]
    
    assert qwen["static_analysis_failures"] == {"ruff": None, "pyright": None}
    assert qwen["defect_density_per_kloc"] == 0.0
    assert qwen["static_density_per_kloc"] == 0.0
    assert qwen["review_density_per_kloc"] == 0.0


def test_coder_since_filter(tmp_path: Path) -> None:
    """--since 필터가 mvp.ts와 review_outcome.ts 기준 최신 날짜로 동작하는지 검증."""
    repo = make_repo(tmp_path)
    
    # old: mvp/review 둘 다 2026-06-01
    write_coding_stats(repo / "issues", 46, {
        "issue": 46,
        "coders": {
            "old_coder": {
                "model": "Old Model",
                "mvp": {"ts": "2026-06-01T10:00:00Z", "loc_added": 100, "static_analysis_failures": {"ruff": 0, "pyright": 0}},
                "review_outcome": {"ts": "2026-06-02T10:00:00Z", "findings_received": 0, "must_fix_count": 0, "good_to_fix_count": 0, "refix_plans_written": 0}
            }
        }
    })
    
    # new: mvp는 2026-06-01 이지만, review_outcome은 2026-07-05
    write_coding_stats(repo / "issues", 47, {
        "issue": 47,
        "coders": {
            "new_coder": {
                "model": "New Model",
                "mvp": {"ts": "2026-06-01T10:00:00Z", "loc_added": 100, "static_analysis_failures": {"ruff": 0, "pyright": 0}},
                "review_outcome": {"ts": "2026-07-05T10:00:00Z", "findings_received": 0, "must_fix_count": 0, "good_to_fix_count": 0, "refix_plans_written": 0}
            }
        }
    })

    proc = run_cli(str(repo), "--since", "2026-07-01", "--json")
    assert proc.returncode == 0
    res = json.loads(proc.stdout)
    coders = res["coders"]
    
    assert "new_coder" in coders
    assert "old_coder" not in coders


def test_coder_corrupt_file_warns_and_continues(tmp_path: Path) -> None:
    """손상된 JSON 파일은 stderr 경고 후 다른 정상 파일 집계를 계속함 (침묵 금지)."""
    repo = make_repo(tmp_path)
    issues_dir = repo / "issues"
    issues_dir.mkdir(parents=True, exist_ok=True)
    
    # 정상 파일
    write_coding_stats(issues_dir, 46, {
        "issue": 46,
        "coders": {
            "sonnet5": {
                "model": "Claude Sonnet 5",
                "mvp": {"ts": "2026-07-13T01:30:50Z", "loc_added": 100, "static_analysis_failures": {"ruff": 0, "pyright": 0}},
                "review_outcome": {"ts": "2026-07-13T21:40:00Z", "findings_received": 0, "must_fix_count": 0, "good_to_fix_count": 0, "refix_plans_written": 0}
            }
        }
    })
    
    # 손상된 파일
    p_corrupt = issues_dir / "issue-47__TYPE-coding-stats.json"
    p_corrupt.write_text("{not valid json}", encoding="utf-8")
    
    proc = run_cli(str(repo))
    assert proc.returncode == 0
    assert "issue-47" in proc.stderr
    
    jproc = run_cli(str(repo), "--json")
    res = json.loads(jproc.stdout)
    assert "sonnet5" in res["coders"]
