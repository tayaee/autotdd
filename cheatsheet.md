# autosdlc 치트시트

issue 파일 기반 TDD 스킬(`tdd2`/`aacpd`/`autotdd`) + 무인 자동 개발/수정 스위트
(`autoqa`/`autofix`/`autodev`/`autoqafix`). GitHub 이슈 없음 — 모든 작업 항목은
`issues/*.md` 파일이다.

## 스킬 계층도 — 뭐가 어느 레벨에 있는지

스킬 수가 많아 헷갈리기 쉬우므로, "사람이 직접 트리거하는 개발 워크플로우"와
"autoqafix 엔진을 감싸는 무인 수정 스위트"를 분리해서 레벨별로 정리한다.

### A. 수동 개발 스킬 (Claude Code 세션에서 사람이 침)

```
/autotddreviewfix             (메타 루프 — 위 /autotdd 를 안에서 재호출)
 이슈당 4단계 무인: 코더 MVP → 리뷰어 N명(병렬) → 플래너(종합) → 코더 재수정
 └─ 리뷰어 성적 집계: python3 tools/reviewer-scoreboard.py <repo> [--json] [--since YYYY-MM-DD]
 └─ Step1·Step4에서 "<coder>-cli.sh -p '/autotdd <N>'" 형태로 호출
 └─ 결합: harness-project 모델 wrapper 5종 (outer sonnet/minimax/qwen/gemini/fable
    + inner 버전고정 sonnet5/minimax3/qwen36/gemini35/fable5)
        │
        ▼
/autotdd                   (오케스트레이터 — 스크립트 없음, 순수 조합)
 이슈 1건을 tdd2 → aacpd 순서로 완전히 끝낸 뒤 다음 이슈로. worktree 옵션 가능.
        │
        ├──▶ /tdd2   구현 (red-green-refactor → verify-issue-#.sh → git add 에서 정지)
        │      └─ 의존: ~/.claude/skills/tdd/ (Matt Pocock 원본 스킬)
        │
        └──▶ /aacpd   병합·배포 (archive → commit → push → deploy --env dev)
               └─ aacp.sh / aacp.bat / aacp.ps1 + defaults/
```

**한 줄 요약**: `tdd2`(구현)+`aacpd`(병합)가 최소 단위 부품, `autotdd`가 이 둘을
이슈당 묶은 조합, `autotddreviewfix`는 그 `autotdd` 자체를 여러 모델이 리뷰·재수정
루프로 감싼 한 단계 더 위 메타 스킬.

### B. 자동 에러 수정(autoqafix) 스위트 (무인 상시 운영 지향)

```
autoqafix-loop.{sh,bat,ps1}         ← ⚠ 아직 미구현(계획 단계). 모든 게 안정되면
 shell:startup 등록 후 상시 무인 운영    실제로 쓰일 **최종 진입점**.
 부팅 3분 대기 → qa→fix 라운드 반복      qa round → fix round 를 한 사이클로
 (페이즈 최소 6시간 간격) → 수정 1건+   묶어 돌리는 상위 래퍼 (docs/autoqafix-design.md
 이면 --reboot-on-fix (24h 4회 초과 시   L82-91 에 설계만 있고 파일은 없음 — git 이력에도
 폭주 가드로 보류)                       커밋된 적 없음. 시나리오 6은 지금은 안 되는 얘기)
        │
        ▼ (역할별로 반복 실행하는 실제 존재 파일)
autoqa-loop / autofix-loop / autodev-loop   (.sh/.bat/.ps1, 지금 실재)
 role-loop.py --role {qa,fix,dev} 를 무한 반복(interval 대기) 실행하는 단일-롤 루프 셸
        │
        ▼ (아래 두 진입점은 서로 대체재 — 둘 다 같은 .py 엔진을 1회 호출)
 ┌────────────────────────────────┬────────────────────────────────┐
 │ 터미널/cron 1회형 (지금 실재)      │ Claude Code 세션 1회형 (지금 실재)  │
 │ autoqa.sh / autofix.sh /        │ /autoqa  /autofix  /autodev  /autoqafix │
 │ autodev.sh / autoqafix-doctor.sh│ SKILL.md 얇은 트리거 — 일하는 LLM은  │
 │ (+ .bat/.ps1), repo 루트에 위치   │ 세션이 아니라 스크립트 내부 래퍼      │
 └────────────────────────────────┴────────────────────────────────┘
        │                                          │
        └────────────────────┬─────────────────────┘
                              ▼ (실제 엔진 — .claude/skills/autoqafix/ 안)
 autoqa.py            ← qa 롤이 호출 (로그 스캔 → issues/autofix-#.md 보고)
 autofix.py           ← fix 롤이 --stream autofix(기본)로, dev 롤이
                          --stream issue 로 동일 스크립트를 호출
                          └─ 항목 처리 시 내부에서 "/autotdd <id> worktree" 를
                             직접 실행 (autofix.py:264) — ↓A의 /autotdd 로 합류
 autoqafix-doctor.py  ← autoqafix 롤이 호출 (엔진 자가 진단)
 autoqafix_core.py    (위 스크립트들이 공유하는 코어 로직)
 error-to-autofix.py, log-scan.py, role-loop.py, select-llm.py,
 usage-{claudecli,minimaxcli,qwencli}.py, wrappers/
```

**한 줄 요약**: 실제 작업은 항상 맨 아래 `.py` 엔진이 한다. 그 엔진을 부르는 방법은
"터미널 1회형(`.sh`)"과 "Claude Code 세션 1회형(`/autoqa` 등 스킬)" 둘 중 아무거나 —
서로 대체재지 상하 관계가 아니다. `*-loop.sh`는 그중 터미널 1회형을 반복 실행하는
셸(지금 존재), `autoqafix-loop`는 qa/fix 두 롤을 한 사이클로 묶어 상시 무인 운영하는
최상위 진입점인데 **아직 파일로는 없다** — 설계 문서(`docs/autoqafix-design.md`)에만
있고, 안정화되면 만들어질 예정. **시나리오 6은 이 미구현 상태를 반영해 아래에서 수정.**

### A·B 합류점

B(자동 수정 엔진)는 완전히 별세계가 아니다 — `autofix.py`가 항목을 처리할 때
내부적으로 `/autotdd <id> worktree`(A)를 그대로 호출한다. `/autotddreviewfix`(A 최상단)도
같은 지점을 호출한다. 즉 실제 코드 작성은 결국 항상 A의 `/tdd2`+`/aacpd` 조합 하나로
수렴하고, B와 `/autotddreviewfix`는 그 위에 "언제·누가·어떤 항목을 무인으로 돌릴지"를
얹은 스케줄러 층일 뿐이다.

## 개념 30초

- **스트림 2개**: `issues/issue-#.md`(사람이 등록) / `issues/autofix-#.md`(autoqa가 로그에서 자동 보고). 번호는 스트림별 독립.
- **상태 = 파일명 접미사**: 없음(기계가 집어감) / `-manual`(사람 몫) / `-agent-failed`(실패 대기) / `-later`(사람이 미룸, 기계는 절대 안 봄).
- **루프 1개 = 앱 repo 1개**, cwd = 대상 repo 루트가 규약의 전부.
- agent는 일회용 worktree에서만 작업 — 사람의 main tree는 절대 안 건드림.

## 시나리오 1 — 이슈 하나를 대화형 TDD로

```
/tdd2 7      # red→green→refactor, verify-issue-7.sh 작성, git add에서 멈춤
/aacpd 7      # archive + commit + push + deploy.sh --env dev
```

번호 생략 시: 진행 중 이슈 재개 또는 가장 작은 번호 제안(1회 확인).

## 시나리오 2 — 남은 이슈 전부 무인 처리 (현재 세션이 구현)

```
/autotdd              # 남은 이슈 나열 → 1회 확인 → 이슈당 tdd2+aacpd 완주
/autotdd 3 5 8        # 지정 이슈만, 한 번에 하나씩 (배치 없음)
/autotdd 7 worktree   # 이슈별 일회용 worktree에서 격리 실행
```

## 시나리오 3 — 새 머신/새 repo에 무인 스위트 배치

```bash
git clone <autosdlc> ~/git/autosdlc && ~/git/autosdlc/install.sh   # 스킬 4종 symlink
cd <대상 앱 repo>
~/git/autosdlc/autoqafix-doctor.sh          # 사전 점검 (FAIL 0이면 준비 완료)
~/git/autosdlc/.claude/skills/autoqafix/wrappers/ping-claudecli.sh  # 실 LLM 응답 확인 (크레딧 소모)
```

대상 repo에 필요한 것: `issues/`, `logs/`(qa 롤일 때), git identity·origin,
선택적으로 `deploy.{sh,ps1,bat} --env dev`(없으면 deploy만 skip).

## 시나리오 4 — 로그에서 결함 자동 보고 (qa 롤)

```bash
cd <대상 앱 repo> && ~/git/autosdlc/autoqa.sh
```

`logs/*.log` 증분 스캔(오프셋 저장) → 미보고 에러 최빈 5개 → 유료 LLM이 본문 작성
→ `issues/autofix-#.md` commit+push. 같은 에러는 dedup-key로 재보고 안 함.

## 시나리오 5 — 등록/보고된 항목 무인 구현 (fix/dev 롤)

```bash
~/git/autosdlc/autofix.sh    # autofix-#.md 담당
~/git/autosdlc/autodev.sh    # issue-#.md 담당 (같은 엔진, 스트림만 다름)
```

항목마다 LLM 재선정 → agent-tier 매칭 → worktree에서 `/autotdd <id> worktree` 실행.
성공 = archive 이동. 실패 = 파일에 `## agent 실패 기록` 추가 후 `-agent-failed` rename.

## 시나리오 6 — Windows 상시 무인 운영 (production)

⚠ **`autoqafix-loop.bat`는 아직 파일로 존재하지 않는다** (설계만
`docs/autoqafix-design.md`에 있음, git 이력에 커밋된 적 없음). qa→fix를 한
사이클로 묶어 재시동까지 하는 합성 루프는 지금은 못 쓴다 — 만들어지기 전까지는
아래처럼 단일 롤 루프를 개별로 `shell:startup`에 등록해서 대체한다:

- 대상 1: `<autosdlc>\autoqa-loop.bat`
- 대상 2: `<autosdlc>\autofix-loop.bat` (또는 `autodev-loop.bat`)
- **"시작 위치" = 대상 앱 repo 루트** (cwd 규약의 전부)

각 `*-loop.bat`은 `role-loop.py --role {qa,fix,dev}`를 무한 반복(페이즈별 최소
6시간 간격)한다. `--reboot-on-fix`·폭주 가드·부팅 3분 대기는 아직 없는
`autoqafix-loop`에만 설계된 기능이라 지금은 적용되지 않는다 — 필요하면 OS
스케줄러(Task Scheduler 등)로 재시동을 직접 구성해야 한다.

## 시나리오 7 — Claude Code 세션에서 1회형

```
/autoqa   /autofix   /autodev   /autoqafix     # cwd = 대상 앱 repo
```

스킬은 얇은 트리거 — 일하는 LLM은 스크립트 내부의 래퍼이지 현재 세션이 아님.

## 시나리오 8 — 사람이 개입할 때

| 접미사 | 대응 |
|---|---|
| `-manual` | 직접 구현 (`/tdd2 <id>` 등) |
| `-agent-failed` | 파일 안 실패 기록 읽고 이슈 보강 → 접미사 떼고 rename+push → 재투입 |
| `-later` | 미룸 표시. 다시 하려면 접미사 제거 |

## LLM 선정 규칙

```bash
export AUTOQAFIX_WRAPPERS="claudecli:paid,minimaxcli:paid,qwencli:local"  # 기본값
uv -q run .claude/skills/autoqafix/select-llm.py --explain   # 판정 근거 표
export AUTOQAFIX_WRAPPER=qwencli                              # 강제 지정
```

유효 잔여율 = min(5시간 쿼터, 주간 쿼터). ≥50%인 유료 중 최대(동률은 목록 앞) →
없으면 로컬 중 available → 전부 불가면 이번 주기 건너뜀.
agent-tier 매칭: 로컬 래퍼는 `local-ok`만, 유료는 `local-ok`+`paid-only`.

## 자주 쓰는 env

| 변수 | 기본 | 용도 |
|---|---|---|
| `AUTOQAFIX_WRAPPER` | (없음) | 래퍼 강제 지정 (usage 조회 생략) |
| `AUTOQAFIX_IMPL_TIMEOUT` | 10800 | 항목당 구현 타임아웃(초) |
| `AUTOQAFIX_INTERVAL` | 21600 | 페이즈 최소 간격(초), `*-loop.sh`가 읽음 |
| `AUTOQAFIX_WRAPPER_DIR` | 스킬 폴더 | 래퍼 디렉토리 대체 |
| `SHUTDOWN_CMD` | — | ⚠ 코드에 미구현. `--reboot-on-fix`용으로 설계만 됨(`autoqafix-loop` 대기 중) |

## 검증 (크레딧 제로)

```bash
for f in regression-tests/verify-*.sh; do bash "$f" || echo "FAIL $f"; done
```

전부 fake 래퍼·픽스처 repo 기반. 실 LLM 확인은 `ping-*` 수동 실행뿐.

## 더 보기

용어: `CONTEXT.md` · 설계: `docs/autoqafix-design.md` · 설치/운영: `docs/SETUP-autoqafix.md`
