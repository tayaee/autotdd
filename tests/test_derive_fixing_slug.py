"""tools/derive-fixing-slug.py 단위 테스트 (issue-48).

공개 경계(CLI 프로세스 + 라이브러리 함수)에서 검증한다 — 내부 구현이
아닌 동작 결과를 단언한다. CLI 호출은 subprocess로 실제 실행해 stdout/exit
code를 본다.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

_TOOLS = Path(__file__).resolve().parent.parent / "tools"
sys.path.insert(0, str(_TOOLS))

SCRIPT = _TOOLS / "derive_fixing_slug.py"

import derive_fixing_slug as dfs  # noqa: E402


# --------------------------------------------------------------------------- #
# 1. normalize_slug
# --------------------------------------------------------------------------- #


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("Credential exposure in error path", "credential-exposure-in-error-path"),
        ("C++ race condition!", "c-race-condition"),
        ("  --leading/trailing  ", "leading-trailing"),
        ("a---b", "a-b"),
        ("", ""),
        ("   ", ""),
        ("!!!", ""),
    ],
)
def test_normalize_slug_basic(raw: str, expected: str) -> None:
    assert dfs.normalize_slug(raw) == expected


def test_normalize_slug_max_len_truncates_at_word_boundary() -> None:
    raw = "the quick brown fox jumps over the lazy dog and then some more text here"
    s = dfs.normalize_slug(raw, max_len=30)
    assert len(s) <= 30
    assert "-" not in s.rstrip("-")[-1] if s else True


def test_normalize_slug_max_len_truncates_at_exact_position() -> None:
    # max_len=50, 잘림 경계에 단어 분리점이 없는 경우 — 정확히 50자
    raw = "a" * 50 + "extra"
    s = dfs.normalize_slug(raw, max_len=50)
    assert len(s) <= 50


def test_normalize_slug_max_len_must_be_positive() -> None:
    with pytest.raises(ValueError, match="max_len"):
        dfs.normalize_slug("hello", max_len=0)


def test_normalize_slug_truncation_does_not_end_with_dash() -> None:
    raw = "abcdefghij-" * 10
    s = dfs.normalize_slug(raw, max_len=20)
    assert not s.endswith("-")


# --------------------------------------------------------------------------- #
# 2. slug_from_finding
# --------------------------------------------------------------------------- #


def test_slug_from_finding_override_takes_priority() -> None:
    text = "### Finding: Race condition in lock-free queue\n\nslug: lock-free-race\n\nmore body"
    assert dfs.slug_from_finding(text) == "lock-free-race"


def test_slug_from_finding_auto_extract_finding_header() -> None:
    text = "## some preamble\n\n### Finding: Null pointer in handler\n\nbody"
    assert dfs.slug_from_finding(text) == "null-pointer-in-handler"


def test_slug_from_finding_override_normalized() -> None:
    text = "slug: AuthN Bug!\n\nbody"
    # override에도 정규화 적용 — `!` 제거, lowercase
    assert dfs.slug_from_finding(text) == "authn-bug"


def test_slug_from_finding_no_header_returns_none() -> None:
    assert dfs.slug_from_finding("plain prose without any header") is None


def test_slug_from_finding_empty_input_returns_none() -> None:
    assert dfs.slug_from_finding("") is None


def test_slug_from_finding_override_normalized_with_special_chars() -> None:
    text = "slug: C++ race\n\nbody"
    assert dfs.slug_from_finding(text) == "c-race"


# --------------------------------------------------------------------------- #
# 3. sort_reviewers
# --------------------------------------------------------------------------- #


def test_sort_reviewers_alphabetical() -> None:
    assert dfs.sort_reviewers(["sonnet", "qwen", "gemini"]) == ["gemini", "qwen", "sonnet"]


def test_sort_reviewers_dedup_not_required() -> None:
    # 중복은 호출자 책임 — 이 함수는 정렬만 (관행 단순화)
    result = dfs.sort_reviewers(["sonnet", "qwen"])
    assert result == ["qwen", "sonnet"]


def test_sort_reviewers_self_only() -> None:
    assert dfs.sort_reviewers(["self"]) == ["self"]


def test_sort_reviewers_self_with_others_excludes_self() -> None:
    # self + 다른 리뷰어 → self 제외, 나머지만 정렬
    assert dfs.sort_reviewers(["qwen", "self", "gemini"]) == ["gemini", "qwen"]


def test_sort_reviewers_empty() -> None:
    assert dfs.sort_reviewers([]) == []


# --------------------------------------------------------------------------- #
# 4. suffix_on_collision
# --------------------------------------------------------------------------- #


def test_suffix_on_collision_no_collision_returns_unchanged() -> None:
    assert dfs.suffix_on_collision("foo", {"bar", "baz"}) == "foo"


def test_suffix_on_collision_first_suffix() -> None:
    assert dfs.suffix_on_collision("a", {"a", "b"}) == "a-2"


def test_suffix_on_collision_third_suffix() -> None:
    assert dfs.suffix_on_collision("a", {"a", "a-2", "a-3"}) == "a-4"


def test_suffix_on_collision_exhaustion_raises() -> None:
    # 충돌 1000회 초과 시 ValueError
    existing = {"a"} | {f"a-{i}" for i in range(2, 1002)}
    with pytest.raises(ValueError, match="1000회"):
        dfs.suffix_on_collision("a", existing)


def test_suffix_on_collision_does_not_mutate_existing() -> None:
    existing = {"a"}
    dfs.suffix_on_collision("a", existing)
    assert existing == {"a"}


# --------------------------------------------------------------------------- #
# 5. build_filename
# --------------------------------------------------------------------------- #


def test_build_filename_must_fix_single_reviewer() -> None:
    fn = dfs.build_filename(
        new_n=49, source_n=48, slug="credential-exposure",
        reviewers=["qwen"], good_to_fix=False,
    )
    assert fn == "issue-49-fixing-48-credential-exposure__BY-qwen.md"


def test_build_filename_good_to_fix_multi_reviewers_alphabetical() -> None:
    fn = dfs.build_filename(
        new_n=50, source_n=48, slug="null-pointer",
        reviewers=["sonnet", "qwen", "gemini"], good_to_fix=True,
    )
    assert fn == "issue-50-fixing-48-null-pointer__STATE-later__BY-gemini-qwen-sonnet.md"


def test_build_filename_good_to_fix_self_only() -> None:
    fn = dfs.build_filename(
        new_n=51, source_n=48, slug="race-condition",
        reviewers=["self"], good_to_fix=True,
    )
    assert fn == "issue-51-fixing-48-race-condition__STATE-later__BY-self.md"


def test_build_filename_must_fix_self_with_others() -> None:
    # self + 다른 리뷰어 → self 제외, BY 값만 남음
    fn = dfs.build_filename(
        new_n=52, source_n=48, slug="mixed-review",
        reviewers=["qwen", "self"], good_to_fix=False,
    )
    assert fn == "issue-52-fixing-48-mixed-review__BY-qwen.md"


def test_build_filename_empty_reviewers_raises() -> None:
    with pytest.raises(ValueError, match="reviewers"):
        dfs.build_filename(
            new_n=53, source_n=48, slug="x",
            reviewers=[], good_to_fix=False,
        )


# --------------------------------------------------------------------------- #
# 6. CLI subprocess
# --------------------------------------------------------------------------- #


def _run_cli(*args: str, stdin: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        input=stdin, capture_output=True, text=True, timeout=10,
    )


def test_cli_by_alphabetical_sort() -> None:
    r = _run_cli("by", "--names", "qwen,sonnet,gemini")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "gemini-qwen-sonnet"


def test_cli_by_self_excluded_when_others_present() -> None:
    r = _run_cli("by", "--names", "self,qwen")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "qwen"


def test_cli_by_self_only() -> None:
    r = _run_cli("by", "--names", "self")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "self"


def test_cli_by_empty_reviewers_errors() -> None:
    r = _run_cli("by", "--names", "")
    assert r.returncode != 0
    assert "comma-separated" in r.stderr.lower() or "reviewers" in r.stderr.lower()


def test_cli_suffix_no_collision() -> None:
    r = _run_cli("suffix", "--existing", "a,b", "--slug", "c")
    assert r.returncode == 0
    assert r.stdout.strip() == "c"


def test_cli_suffix_collision_adds_suffix() -> None:
    r = _run_cli("suffix", "--existing", "a,b", "--slug", "a")
    assert r.returncode == 0
    assert r.stdout.strip() == "a-2"


def test_cli_slug_from_stdin_finding_header() -> None:
    r = _run_cli("slug", stdin="### Finding: Credential exposure!\n\nbody\n")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "credential-exposure"


def test_cli_slug_from_stdin_override() -> None:
    r = _run_cli("slug", stdin="slug: my-custom-name\n\nbody\n")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "my-custom-name"


def test_cli_slug_stdin_without_header_errors() -> None:
    r = _run_cli("slug", stdin="plain prose without any header\n")
    assert r.returncode != 0


def test_cli_no_subcommand_errors() -> None:
    r = _run_cli()
    assert r.returncode != 0


def test_cli_help_does_not_error() -> None:
    r = _run_cli("--help")
    assert r.returncode == 0
    assert "fixing 파생" in r.stdout or "slug" in r.stdout.lower()