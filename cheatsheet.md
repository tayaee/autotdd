# autotdd 치트시트

issue 파일 기반 TDD 스킬(`tdd2`/`acpd`/`autotdd`) + 무인 자동 개발/수정 스위트
(`autoqa`/`autofix`/`autodev`/`autoqafix`). GitHub 이슈 없음 — 모든 작업 항목은
`issues/*.md` 파일이다.

## 개념 30초

- **스트림 2개**: `issues/issue-#.md`(사람이 등록) / `issues/autofix-#.md`(autoqa가 로그에서 자동 보고). 번호는 스트림별 독립.
- **상태 = 파일명 접미사**: 없음(기계가 집어감) / `-manual`(사람 몫) / `-agent-failed`(실패 대기) / `-later`(사람이 미룸, 기계는 절대 안 봄).
- **루프 1개 = 앱 repo 1개**, cwd = 대상 repo 루트가 규약의 전부.
- agent는 일회용 worktree에서만 작업 — 사람의 main tree는 절대 안 건드림.

## 시나리오 1 — 이슈 하나를 대화형 TDD로

```
/tdd2 7      # red→green→refactor, verify-issue-7.sh 작성, git add에서 멈춤
/acpd 7      # archive + commit + push + deploy.sh --env dev
```

번호 생략 시: 진행 중 이슈 재개 또는 가장 작은 번호 제안(1회 확인).

## 시나리오 2 — 남은 이슈 전부 무인 처리 (현재 세션이 구현)

```
/autotdd              # 남은 이슈 나열 → 1회 확인 → 이슈당 tdd2+acpd 완주
/autotdd 3 5 8        # 지정 이슈만, 한 번에 하나씩 (배치 없음)
/autotdd 7 worktree   # 이슈별 일회용 worktree에서 격리 실행
```

## 시나리오 3 — 새 머신/새 repo에 무인 스위트 배치

```bash
git clone <autotdd> ~/git/autotdd && ~/git/autotdd/install.sh   # 스킬 4종 symlink
cd <대상 앱 repo>
~/git/autotdd/autoqafix-doctor.sh          # 사전 점검 (FAIL 0이면 준비 완료)
~/git/autotdd/.claude/skills/autoqafix/wrappers/ping-claudecli.sh  # 실 LLM 응답 확인 (크레딧 소모)
```

대상 repo에 필요한 것: `issues/`, `logs/`(qa 롤일 때), git identity·origin,
선택적으로 `deploy.{sh,ps1,bat} --env dev`(없으면 deploy만 skip).

## 시나리오 4 — 로그에서 결함 자동 보고 (qa 롤)

```bash
cd <대상 앱 repo> && ~/git/autotdd/autoqa.sh
```

`logs/*.log` 증분 스캔(오프셋 저장) → 미보고 에러 최빈 5개 → 유료 LLM이 본문 작성
→ `issues/autofix-#.md` commit+push. 같은 에러는 dedup-key로 재보고 안 함.

## 시나리오 5 — 등록/보고된 항목 무인 구현 (fix/dev 롤)

```bash
~/git/autotdd/autofix.sh    # autofix-#.md 담당
~/git/autotdd/autodev.sh    # issue-#.md 담당 (같은 엔진, 스트림만 다름)
```

항목마다 LLM 재선정 → agent-tier 매칭 → worktree에서 `/autotdd <id> worktree` 실행.
성공 = archive 이동. 실패 = 파일에 `## agent 실패 기록` 추가 후 `-agent-failed` rename.

## 시나리오 6 — Windows 상시 무인 운영 (production)

`shell:startup` 지름길 생성:

- 대상: `<autotdd>\autoqafix-loop.bat --reboot-on-fix`
- **"시작 위치" = 대상 앱 repo 루트** (cwd 규약의 전부)

동작: 부팅 3분 대기 → qa→fix 라운드 반복(페이즈별 최소 6시간 간격) → 수정 1건 이상이면
재시동(24시간 4회 초과 시 폭주 가드로 보류). 단일 롤만 돌리려면
`autoqa-loop.bat` / `autofix-loop.bat` / `autodev-loop.bat`.

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
| `AUTOQAFIX_INTERVAL` | 21600 | 페이즈 최소 간격(초) |
| `SHUTDOWN_CMD` | OS 기본 | `--reboot-on-fix`의 재시동 명령 대체 |
| `AUTOQAFIX_WRAPPER_DIR` | 스킬 폴더 | 래퍼 디렉토리 대체 |

## 검증 (크레딧 제로)

```bash
for f in regression-tests/verify-*.sh; do bash "$f" || echo "FAIL $f"; done
```

전부 fake 래퍼·픽스처 repo 기반. 실 LLM 확인은 `ping-*` 수동 실행뿐.

## 더 보기

용어: `CONTEXT.md` · 설계: `docs/autoqafix-design.md` · 설치/운영: `docs/SETUP-autoqafix.md`
