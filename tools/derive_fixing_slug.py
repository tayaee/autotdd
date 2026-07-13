#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""derive-fixing-slug — fixing 파생 이슈 파일명 빌더 헬퍼 (issue-48).

autotddreview의 Step 5가 리뷰 finding마다 만드는 파생 이슈 파일명 형식
`issue-<신번호>-fixing-<원본>-<finding-slug>__STATE-later__BY-<r1>-<r2>-...md`
(또는 good_to_fix=False이면 `__STATE-later` 없음)을 결정성 있게 조립한다.

3개 결정적 로직:
- 정규화: finding 제목/override 값 → kebab-lowercase 슬러그 (50자 truncate)
- BY 정렬: 복수 리뷰어 base명 알파벳 정렬 후 하이픈 연결, `self`는 예약값
- 충돌 suffix: 같은 issue 번호 내 슬러그 충돌 시 `-2`, `-3` 자동 부여

공개 함수 (라이브러리):
    normalize_slug(value, *, max_len=50)
    slug_from_finding(finding_text, *, max_len=50)
    sort_reviewers(reviewers)
    suffix_on_collision(slug, existing)
    build_filename(*, new_n, source_n, slug, reviewers, good_to_fix)

CLI (argparse subcommands):
    derive-fixing-slug.py slug [--max-len 50]    # stdin: finding 본문 → stdout: 슬러그
    derive-fixing-slug.py by --names "a,b,c"    # stdout: "a-b-c" (알파벳 정렬)
    derive-fixing-slug.py suffix --existing "..." --slug "..." # stdout: 충돌 시 suffix
"""
from __future__ import annotations

import argparse
import re
import sys
from typing import Iterable

# --------------------------------------------------------------------------- #
# 정규화
# --------------------------------------------------------------------------- #

_NON_ALNUM = re.compile(r"[^a-z0-9]+")
_MULTI_DASH = re.compile(r"-+")
_OVERRIDE = re.compile(r"(?m)^slug:\s*(\S.*?)\s*$")
_FINDING_HEADER = re.compile(r"(?m)^#{1,6}\s+Finding:\s*(.+?)\s*$")


def normalize_slug(value: str, *, max_len: int = 50) -> str:
    """임의의 문자열을 kebab-lowercase 슬러그로 변환.

    단계:
        1. lowercase
        2. [^a-z0-9]+ 묶음을 '-'로 치환 (영숫자만 보존)
        3. 연속 '-' 1개로 압축
        4. 양끝 '-' strip
        5. max_len truncate (단어 경계에서 자름 — 50자 이하면 그대로)
        6. truncate 후 다시 양끝 strip

    Args:
        value: 원본 문자열.
        max_len: 최대 길이. 0 이하면 ValueError.

    Returns:
        정규화된 슬러그. 입력이 비어 있거나 모두 비영숫자이면 빈 문자열.
    """
    if max_len <= 0:
        raise ValueError(f"max_len must be > 0, got {max_len}")
    s = value.lower()
    s = _NON_ALNUM.sub("-", s)
    s = _MULTI_DASH.sub("-", s)
    s = s.strip("-")
    if not s:
        return ""
    if len(s) > max_len:
        s = s[:max_len].rsplit("-", 1)[0].rstrip("-") if "-" in s[:max_len] else s[:max_len].rstrip("-")
        s = s.rstrip("-")
    return s


# --------------------------------------------------------------------------- #
# finding 본문 → 슬러그
# --------------------------------------------------------------------------- #


def slug_from_finding(finding_text: str, *, max_len: int = 50) -> str | None:
    """finding 본문에서 override (`slug: <name>` 헤더) 또는 자동 추출
    (`### Finding: <title>`) → normalize_slug.

    우선순위: override > 자동 추출. 둘 다 없거나 결과가 빈 문자열이면 None.
    """
    if not finding_text:
        return None
    # override 먼저
    m = _OVERRIDE.search(finding_text)
    if m:
        s = normalize_slug(m.group(1), max_len=max_len)
        return s or None
    # 자동 추출
    m = _FINDING_HEADER.search(finding_text)
    if m:
        s = normalize_slug(m.group(1), max_len=max_len)
        return s or None
    return None


# --------------------------------------------------------------------------- #
# BY 정렬
# --------------------------------------------------------------------------- #


def sort_reviewers(reviewers: Iterable[str]) -> list[str]:
    """복수 리뷰어 base명을 알파벳 정렬.

    `self`는 예약값(셀프 리뷰, spec 46줄) — 정렬 대상에서 제외.
    - self만 있으면 `['self']`.
    - self와 다른 리뷰어가 혼합되면 self 제외, 나머지만 정렬.
    - 빈 입력 → `[]`.
    """
    items = list(reviewers)
    has_self = "self" in items
    others = sorted(r for r in items if r != "self")
    if has_self and not others:
        return ["self"]
    return others


# --------------------------------------------------------------------------- #
# 충돌 suffix
# --------------------------------------------------------------------------- #

_MAX_SUFFIX_TRIES = 1000


def suffix_on_collision(slug: str, existing: set[str]) -> str:
    """`existing`에 slug가 없으면 그대로 반환. 있으면 `-2`, `-3`, ... 시도.

    1000회 시도 후에도 충돌이면 ValueError (침묵 금지).
    `existing`은 호출자 책임으로 mutable 복사하거나 read-only 그대로 넘긴다
    (이 함수는 `existing`을 변경하지 않음).
    """
    if slug not in existing:
        return slug
    for n in range(2, _MAX_SUFFIX_TRIES + 2):
        candidate = f"{slug}-{n}"
        if candidate not in existing:
            return candidate
    raise ValueError(
        f"suffix_on_collision: {slug!r} 충돌 1000회 초과 (existing size={len(existing)})"
    )


# --------------------------------------------------------------------------- #
# 파일명 빌드
# --------------------------------------------------------------------------- #


def build_filename(
    *,
    new_n: int,
    source_n: int,
    slug: str,
    reviewers: list[str],
    good_to_fix: bool,
) -> str:
    """파생 이슈 파일명을 조립한다.

    good_to_fix=True  → `issue-<new>-fixing-<src>-<slug>__STATE-later__BY-<r1>-...md`
    good_to_fix=False → `issue-<new>-fixing-<src>-<slug>__BY-<r1>-...md`

    BY 값은 sort_reviewers 결과를 사용 (`self` 규칙 적용).
    reviewers가 빈 리스트면 ValueError (BY 슬롯은 빈 값 불가).
    """
    if not reviewers:
        raise ValueError("build_filename: reviewers must not be empty")
    sorted_rvs = sort_reviewers(reviewers)
    by_value = "-".join(sorted_rvs)
    by_part = f"__BY-{by_value}"
    state_part = "__STATE-later" if good_to_fix else ""
    tags = [t for t in (state_part, by_part) if t]
    tags_str = "".join(tags)
    if tags_str:
        return f"issue-{new_n}-fixing-{source_n}-{slug}{tags_str}.md"
    return f"issue-{new_n}-fixing-{source_n}-{slug}.md"


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def _cli_slug(args: argparse.Namespace) -> int:
    text = sys.stdin.read() if not sys.stdin.isatty() else ""
    slug = slug_from_finding(text, max_len=args.max_len)
    if slug is None:
        print("error: stdin에 `slug:` 또는 `### Finding:` 헤더 없음", file=sys.stderr)
        return 1
    print(slug)
    return 0


def _cli_by(args: argparse.Namespace) -> int:
    names = [r.strip() for r in args.names.split(",") if r.strip()]
    if not names:
        print("error: --names는 comma-separated 비어있지 않은 값이어야 함", file=sys.stderr)
        return 1
    sorted_rvs = sort_reviewers(names)
    print("-".join(sorted_rvs))
    return 0


def _cli_suffix(args: argparse.Namespace) -> int:
    existing = {s.strip() for s in args.existing.split(",") if s.strip()}
    result = suffix_on_collision(args.slug, existing)
    print(result)
    return 0


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="fixing 파생 이슈 슬러그/BY/suffix 결정적 빌더")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_slug = sub.add_parser("slug", help="stdin finding 본문 → 슬러그")
    p_slug.add_argument("--max-len", type=int, default=50)
    p_slug.set_defaults(func=_cli_slug)

    p_by = sub.add_parser("by", help="comma-separated 리뷰어 → 알파벳 정렬 후 하이픈 연결")
    p_by.add_argument("--names", required=True, help="comma-separated 리뷰어 base명 (예: qwen,sonnet,gemini,self)")
    p_by.set_defaults(func=_cli_by)

    p_suf = sub.add_parser("suffix", help="충돌 시 suffix 부여")
    p_suf.add_argument("--existing", required=True, help="comma-separated 기존 슬러그 집합")
    p_suf.add_argument("--slug", required=True)
    p_suf.set_defaults(func=_cli_suffix)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())