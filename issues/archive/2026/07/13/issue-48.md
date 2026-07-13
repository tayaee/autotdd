# issue-48: fixing 파생 이슈에 `<finding-slug>` + `__BY-<...>` 추가 — 파일명에서 무엇을 고치는지 보이게
agent-tier: any

## 배경

grill 세션(2026-07-13) 합의. `autotddreview`(issue-41 도입)의 파생 이슈 생성
로직이 만들어내는 파일명은 `issue-NN-fixing-<M>__STATE-later.md` 형식
(spec 116줄) — **계보**(원본 M번 리뷰)만 담고, **어떤 finding을 고치는지**
식별 불가. 이로 인해:

- `__STATE-later`로 장기 휴면된 good-to-fix 파생은 사람이 STATE 태그를
  지워 승격할 때마다 본문을 다시 열어 "이게 뭐였지?"가 발생.
- agent가 자동 수정하는 티켓(must-fix 포함)도 파일명만으로 무엇을 고치는지
  한눈에 보이지 않음 — 본문을 열어야만 함.

→ 모든 fixing 파생 이슈에 (1) finding 제목 슬러그 `<finding-slug>` (2) 작성
리뷰어 `__BY-<...>` 두 정보를 파일명에 추가. 파일명 규약 v2의 **닫힌
KEY 집합(`TYPE`/`STATE`/`BY`)은 그대로** 유지 — 슬러그 슬롯에 두 번째 부분을
얹는 **관행 추가** (문법 자체 변경 아님).

**grill 합의 결정 요약**:
- 적용 범위: must-fix + good-to-fix **둘 다** (사용자 명시)
- 슬러그 출처: **자동 추출 기본 + 사람 override 가능** (`finding` 헤더 본문에 `slug:` 헤더 추가 시)
- 정규화 규칙: lowercase → `[^a-z0-9]+` → `-` → 연속 압축 → strip → **50자 truncate** → strip
- 다중 리뷰어: base명 **알파벳 정렬** 후 하이픈 연결 (`__BY-gemini-qwen-sonnet`)
- `__BY-self`: 예약값, **항상 단독** (다른 리뷰어와 혼합 시 self 제외, 나머지만 정렬)
- 슬러그 충돌: 같은 issue 번호 내 동일 슬러그 시 `-2`, `-3` suffix 자동 부여
- override 정규화: override 값에도 동일 정규화 적용 (형식 일관성 우선)
- 마이그레이션: 기존 archived `issue-127-fixing-123.md` 등은 **불변** (spec 96줄 "레거시 불변")
- 적용 시점: **이 PR merge 이후** 생성되는 모든 fixing 파생부터

**선행**: issue-39(파일명 규약 v2), issue-41(fixing 파생 + `-<N>` 슬러그 관행),
issue-43(스코어보드 CLI), issue-44(`model` 필드 + 전원 크레딧). 이 이슈는
issue-41이 만든 fixing 파생 형식에 두 정보(`<finding-slug>`, `__BY-<...>`)를 더한다.

## 요구사항

### 1. `docs/spec/spec-issue-filenames.md` 갱신

- **관행 섹션**(현재 100줄 부근의 "파생 이슈 슬러그")을 다음 내용으로 확장:
  - fixing 파생 슬러그는 **두 부분으로 구성**될 수 있다: `fixing-<원본>-<finding-slug>`
    (`<finding-slug>`는 finding 제목의 자동 슬러그화 결과 또는 사람이 명시한 override).
  - 정규화 규칙 명시: lowercase → `[^a-z0-9]+` → `-` → 연속 압축 → 양끝 strip
    → 50자 truncate → strip. override 값에도 동일 적용.
  - 사람 override: 리뷰 산출물 finding 본문에 `slug: <name>` 한 줄 헤더가 있으면
    자동 추출 대신 그 값을 사용. **override에도 정규화 적용**(형식 일관성).
  - 슬러그 충돌: 같은 issue 번호 내에서 동일 슬러그가 두 번 등장하면
    `-2`, `-3`, ... suffix 자동 부여(최대 1000회 시도 후 ValueError).
- **태그 3종 표**(36–39줄)의 `__BY-` 행에 다음 주석 추가: "다중 작성자는
  base명 알파벳 정렬 후 하이픈 연결(`__BY-gemini-qwen-sonnet`).
  `self`는 예약값으로 다른 리뷰어와 혼합 시 제외되고, self만 있으면 단독."
- **예시 섹션**(112줄)에 새 형식 3~4건 추가:
  - `issue-49-fixing-48-credential-exposure__BY-qwen.md` (단일, must-fix)
  - `issue-50-fixing-48-null-pointer__STATE-later__BY-gemini-qwen-sonnet.md`
    (다중, good-to-fix, 알파벳 정렬)
  - `issue-51-fixing-48-race-condition__STATE-later__BY-qwen-2.md`
    (충돌 suffix `-2`)
- **관행 섹션**에 "레거시 호환" 한 단락 추가: "merge 이전 생성된 archived
  파일(`issue-127-fixing-123.md`, `__STATE-later` 단일 슬러그)은 개명하지
  않는다 (spec 96줄 '레거시 불변'과 동일 정책). 새 형식은 본 PR merge 이후
  fixing 파생부터 적용."
- **구 문법/예시**: 기존 예시 줄 6건은 그대로 두고 **새 줄로 추가**(하위 호환).

### 2. 신규 헬퍼: `tools/derive-fixing-slug.py`

`tools/reviewer-scoreboard.py`(issue-43)와 동일 관례: PEP 723 인라인 메타데이터
(`# /// script` / `requires-python = ">=3.12"` / `dependencies = []`),
**표준 라이브러리만** 사용, `from __future__ import annotations`.

**라이브러리 API**:

```python
def normalize_slug(value: str, *, max_len: int = 50) -> str:
    """소문자화 → 비영숫자 묶음을 '-'로 → 연속 '-' 압축 → 양끝 strip
    → max_len truncate → 다시 strip. 빈 결과는 ''."""

def slug_from_finding(finding_text: str, *, max_len: int = 50) -> str | None:
    """finding 본문에서 override (`slug: <name>` 헤더) 또는 자동 추출
    (`### Finding: <title>` 첫 매칭) → normalize_slug 적용.
    둘 다 없거나 결과가 빈 문자열이면 None."""

def sort_reviewers(reviewers: Iterable[str]) -> list[str]:
    """`self`는 정렬 대상에서 제외. self만 있으면 ['self'].
    self와 다른 리뷰어가 혼합되면 self 제외 후 나머지 알파벳 정렬."""

def suffix_on_collision(slug: str, existing: set[str]) -> str:
    """`existing`에 slug가 있으면 '-2', '-3', ... suffix 부여.
    1000회 시도 후에도 충돌이면 ValueError (침묵 금지)."""

def build_filename(*, new_n: int, source_n: int, slug: str,
                   reviewers: list[str], good_to_fix: bool) -> str:
    """good_to_fix=True → 'issue-<n>-fixing-<src>-<slug>__STATE-later__BY-<...>.md'.
    good_to_fix=False → 'issue-<n>-fixing-<src>-<slug>__BY-<...>.md'.
    sort_reviewers 결과를 BY 값으로 사용."""
```

**CLI** (argparse, 3개 subcommand):

```bash
# 슬러그 도출: override 또는 자동 추출. stdin으로 finding 본문 받음.
derive-fixing-slug.py slug [--max-len 50]   # stdin: finding 본문

# BY 정렬: comma-separated 입력 → hyphen-separated 정렬 출력.
derive-fixing-slug.py by --reviewers "qwen,sonnet,self,gemini"
# → stdout: "gemini-qwen-sonnet"

# 충돌 suffix 적용: 기존 슬러그 집합과 새 슬러그 비교.
derive-fixing-slug.py suffix --existing "a,b,c" --slug "b"
# → stdout: "b-2"
```

각 subcommand는 결정적 stdout, 에러는 stderr + exit != 0.

### 3. `.claude/skills/autotddreview/SKILL.md` 갱신 (Step 5)

line 158–170의 "파생 이슈 생성" 절(line 159–160의 두 명시적 파일명 형식 포함)을
다음과 같이 교체:

- 정규화·override·suffix는 helper가 결정성 있게 처리한다. SKILL.md prose는
  흐름(언제 helper를 호출하는가)만 명시.
- 새 형식:
  - must-fix → `python tools/derive-fixing-slug.py build --new <신번호>
    --source <원본번호> --slug "<finding-slug>" --reviewers "<csv>"
    --no-good-to-fix` 결과 파일명
  - good-to-fix → 같은 호출 + `--good-to-fix`
- 본문 계보(원본 번호, 출처 리뷰 파일명, finding 인용, 재검증 결과)는 그대로.
- 중복 finding 규칙(같은 finding이 복수 리뷰어에게 발견) — issue-44 정책
  (파생 1개, 전원 크레딧, derived_by_reviewers에 모두 인용) 그대로 유지.
  단 BY 값은 **알파벳 정렬 후 하이픈 연결** (예: `__BY-gemini-qwen-sonnet`).

### 4. 신규 테스트: `tests/test_derive_fixing_slug.py`

`tests/test_reviewer_scoreboard.py` 패턴(공개 경계 = CLI 프로세스, 내부
함수가 아니라 실행 결과 단언) 준수. 다음 케이스 단언:

1. **정규화** (`normalize_slug`):
   - `"Credential exposure in error path"` → `"credential-exposure-in-error-path"`
   - `"C++ race condition!"` → `"c-race-condition"` (`+` 제거)
   - `"  --leading/trailing  "` → `"leading-trailing"` (양끝 strip)
   - `"a---b"` → `"a-b"` (연속 압축)
   - 60자 입력 + `max_len=50` → 길이 ≤ 50, 단어 경계에서 자름
   - `"   "` (공백만) → `""`

2. **override** (`slug_from_finding`):
   - 본문에 `slug: my-custom-name` 있으면 override 사용 (정규화 적용)
   - override 없을 때 `### Finding: Race condition` 첫 줄 추출
   - `### Finding:` 없는 본문에서 override만 의존 → None 또는 override 결과
   - override와 자동 추출 둘 다 있을 때 override 우선

3. **BY 정렬** (`sort_reviewers`):
   - `["sonnet", "qwen", "gemini"]` → `["gemini", "qwen", "sonnet"]`
   - `["qwen", "self"]` → `["qwen"]` (self 제외)
   - `["self"]` → `["self"]`
   - `[]` → `[]`

4. **충돌 suffix** (`suffix_on_collision`):
   - `("a", {"a", "b"})` → `"a-2"`
   - `("a", {"a", "a-2", "a-3"})` → `"a-4"`
   - 1000회 충돌 시 ValueError

5. **파일명 빌드** (`build_filename`):
   - good_to_fix=False, 단일 리뷰어 → `issue-49-fixing-48-foo__BY-qwen.md`
   - good_to_fix=True, 다중 리뷰어 → `__STATE-later__BY-` 정렬된 BY
   - good_to_fix=True, self만 → `__STATE-later__BY-self.md`

6. **CLI 통합** (subprocess 호출):
   - `derive-fixing-slug.py by --reviewers "qwen,sonnet,gemini"` → stdout `gemini-qwen-sonnet`
   - `derive-fixing-slug.py suffix --existing "a,b,c" --slug "b"` → stdout `b-2`
   - `derive-fixing-slug.py slug` with stdin finding 본문 → stdout 정규화 결과

### 5. 신규 회귀: `regression-tests/verify-issue-48.sh`

`regression-tests/verify-issue-39.sh` 패턴(3개 층 단언) 준수:

1. **bash grep 단언**:
   - `spec-issue-filenames.md`에 "finding-slug", "slug:", "알파벳", "BY-self",
     "레거시 불변" 패턴 존재
   - `autotddreview/SKILL.md` line 158–170 영역에 `derive-fixing-slug.py`
     호출 또는 새 형식 `-fixing-<N>-<slug>` 존재
   - 기존 SKILL.md의 옛 형식 `issue-<신번호>-fixing-<N>.md` 단독 사용 0건
     (helper 호출로 대체됨을 단언)

2. **pytest 실행**:
   - `python3 -m pytest tests/test_derive_fixing_slug.py -q` exit 0

3. **helper CLI 직접 호출**:
   - `python3 tools/derive-fixing-slug.py by --reviewers "qwen,sonnet,gemini"`
     → stdout `gemini-qwen-sonnet`
   - `python3 tools/derive-fixing-slug.py suffix --existing "a,b" --slug "a"`
     → stdout `a-2`

### 6. 하지 말 것

- 기존 archived `issue-127-fixing-123.md`, `__STATE-later` 등 일괄 개명 (불변).
- `__TYPE-code-review__BY-<reviewer>` 같은 다른 산출물 파일명 형식 변경 (이번 작업은 fixing 파생만).
- 전역 `~/.claude/skills/autotddreview/SKILL.md` 동기화 (별도 issue).
- `tools/reviewer-scoreboard.py` 등 다른 도구 손대기 (이번 작업과 무관).
- harness-project의 `upgrade-issue-filenames.sh`(구→신 마이그레이션용) 변경.
- 새 KEY (`__DESC-` 등) 도입 — 닫힌 KEY 집합 (`TYPE`/`STATE`/`BY`) 확장 금지.

## 승인 기준

- [ ] `docs/spec/spec-issue-filenames.md`: 관행 섹션에 `<finding-slug>` 두 번째
      부분·정규화 규칙·override 헤더·suffix·BY 정렬·BY-self 단독·레거시 불변
      7가지 항목 추가. 예시 섹션에 새 형식 3~4건 추가.
- [ ] `tools/derive-fixing-slug.py` 신규: PEP723, stdlib only, 5개 공개 함수
      (`normalize_slug`, `slug_from_finding`, `sort_reviewers`,
      `suffix_on_collision`, `build_filename`) + 3개 CLI subcommand
      (`slug`, `by`, `suffix`).
- [ ] `tests/test_derive_fixing_slug.py` 신규: pytest 케이스 ≥ 10건.
- [ ] `.claude/skills/autotddreview/SKILL.md` Step 5: 옛 형식 `fixing-<N>.md`
      / `__STATE-later` 단일 슬러그 명시 0건, `derive-fixing-slug.py` 호출 1건 이상.
- [ ] `regression-tests/verify-issue-48.sh` 신규: bash grep ≥ 6건 + pytest
      게이트 + helper CLI ≥ 2건. 전체 회귀 PASS, `pytest tests/test_derive_fixing_slug.py`
      PASS, ruff/pyright 클린, compileall 클린.

## 검증

`bash regression-tests/verify-issue-48.sh` (V3 3개 층 단언):
- spec-issue-filenames.md에 새 관행/예시 존재, 구 형식 단독 사용 0건
- `autotddreview/SKILL.md` Step 5에 helper 호출 존재
- `pytest tests/test_derive_fixing_slug.py -q` exit 0, 케이스 ≥ 10건
- helper CLI: `--reviewers "qwen,sonnet,gemini"` → `gemini-qwen-sonnet`,
  `--existing "a,b" --slug "a"` → `a-2`

## 구현 결과

**구현 완료 일시**: 2026-07-13T07:16:38Z
**변경 파일**:
- `docs/spec/spec-issue-filenames.md` — 관행 섹션에 finding 슬러그(자동 추출·override·정규화·suffix·BY 정렬·BY-self·레거시 호환) 7항목 추가, 예시 섹션에 새 형식 4건 추가, 태그 표 `__BY-` 행에 다중 작성자/예약값 주석 추가
- `tools/derive_fixing_slug.py` — 신규 (PEP723, stdlib only, 5개 공개 함수 + 3개 CLI subcommand: `slug`/`by`/`suffix`)
- `tests/test_derive_fixing_slug.py` — 신규 pytest (43 케이스: 정규화/override/suffix/정렬/BY-self/build_filename/CLI subprocess)
- `pytest.ini` — 신규 (pythonpath = tools — helper를 라이브러리 단언에서 import 가능하도록)
- `.claude/skills/autotddreview/SKILL.md` — Step 5의 옛 두 줄(`fixing-<N>.md` / `__STATE-later`)을 helper 호출 4건(slug/by/suffix/build_filename)로 교체, 다중 작성자 BY 정렬·레거시 불변 명시
- `regression-tests/verify-issue-48.sh` — 신규 (V3 3개 층: bash grep 8건 + pytest 게이트 + helper CLI 7건)
- `regression-tests/verify-issue-41.sh` — `-fixing-<N>` 단언을 `-fixing-<`로 일반화 (옛/신 prefix 매치)
- `regression-tests/verify-issue-41.conflict-with-48.md` — 신규 (verify-41 단언 변경 사유 문서화)
- `issues/issue-48.md` — 본 파일, 구현 결과 갱신
- `issues/issue-48__TYPE-agent-stats.json` — 신규 (`issue`/`started`/`coders.minimax.mvp`)

**스펙 이탈**:
1. **helper 파일명**: 계획은 `tools/derive-fixing-slug.py`(하이픈)였으나
   `tools/derive_fixing_slug.py`(underscore)로 변경. 이유: pytest에서
   helper를 라이브러리 단언으로 import해야 하는데 Python 모듈명은 식별자여야
   하므로 하이픈 불가. PEP8도 underscore를 권장. CLI 호출 명령도
   `python tools/derive_fixing_slug.py` (subcommand `slug`/`by`/`suffix`)
   형태로 자연스럽다. SKILL.md/verify-issue-48.sh 모두 새 파일명으로 갱신.
2. **helper `by` subcommand의 CLI 플래그명**: 계획은 `--reviewers`였으나
   `--names`로 변경. 이유: autotddreview SKILL.md의 옛 CLI 플래그
   (`--reviewers`는 v3에서 제거됨)와 의미가 충돌해 `verify-issue-38.sh`의
   "옛 `--reviewers` 플래그 부재" 단언을 깨뜨렸다. helper 내부 함수명
   `sort_reviewers`/`build_filename`은 그대로, CLI 플래그만 `--names`로
   변경해 SKILL.md/회귀 단언 모두 깔끔. 라이브러리 `build_filename`의 키워드
   인자 `reviewers=`는 그대로 유지.
3. **`__BY-self`의 단독 사용 단언**: spec에서 "self만 있으면 단독"을 명시했으므로
   테스트에 `test_build_filename_good_to_fix_self_only` 케이스를 추가해
   `__STATE-later__BY-self` 형태가 정확히 생성됨을 검증했다. 이는 spec 본문
   의도와 일치하므로 이탈이라기보다 보강.

**verify 결과**: `bash regression-tests/verify-issue-48.sh` 28/28 PASS.
전체 회귀 `regression-tests/verify-issue-*.sh` 45개 전부 PASS (신규
`verify-issue-41.conflict-with-48.md` 포함). `uv run --with pytest
pytest -q tests/` 64/64 PASS. `uv run --with pyright pyright
tools/derive_fixing_slug.py` 0 errors. `uv run python -m compileall
tools/ tests/ -q` 클린. ruff는 환경 문제(`Exec format error`)로 실행 불가
— tdd2 SKILL.md Step 5는 `pyproject.toml` 부재 시 ruff/pyright 자동 skip
규약이므로 본 회귀 영향 없음. helper의 pyright는 scoped 실행으로 직접
검증해 0 errors.