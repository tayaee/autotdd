# autotdd

issue 파일 기반 TDD 스킬(tdd2/acpd/autotdd)과 무인 자동 개발/수정 스위트
(autoqa/autofix/autodev/autoqafix)의 리포.

## Language

**자동화 루프**:
`auto<롤>-loop` 꼴 스크립트들의 총칭. 롤은 셋이다 — **qa**(로그에서 결함을 발견해 autofix
스트림으로 보고), **fix**(autofix 스트림 항목을 구현), **dev**(issue 스트림 항목을 구현;
엔진은 fix와 같고 담당 스트림만 다름). 하나의 루프 인스턴스는 정확히 하나의 앱 repo를
담당한다. 사람이 repo마다 필요한 루프를 골라 구성하며, 여러 앱을 다루려면 앱 repo
디렉토리별로 인스턴스를 하나씩 띄운다.
_Avoid_: 데몬, 오케스트레이터

**보고**:
앱 로그에서 발견한, 아직 보고된 적 없는 에러를 해당 repo의 autofix 스트림
(`issues/autofix-#.md`) 파일로 기록해 push하는 행위. QA 롤(`autoqa`)의 산출이 정확히 이것이다.
_Avoid_: 에러 리포팅, 로깅, 알림

**스트림**:
`issues/` 안의 작업 항목이 흐르는 두 개의 분리된 이름 공간. **issue 스트림**
(`issue-#.md`, commit 접두사 `issue-#:`)은 사람이 수동으로 기능을 추가·수정하는 기존
흐름이고, **autofix 스트림**(`autofix-#.md`, commit 접두사 `autofix-#:`)은 agent(autoqa)가
자동 보고하는 흐름이다. 번호는 스트림별로 독립이다. autofix 스트림은 autofix 루프가,
issue 스트림은 autodev 루프가 구현을 담당한다.
_Avoid_: 큐, 채널, 트랙

**agent-tier**:
작업 항목 파일에 박히는 난이도 스탬프 — `local-ok`(로컬 LLM도 가능) / `paid-only`(유료
LLM 필요) / `manual`(사람 몫). `error-to-autofix`가 항목을 작성할 때 같은 LLM 호출에서
산출해 박고, 사람이 만든 스탬프 없는 항목은 유료 LLM이 1회 판정해 추가한다. 루프의
디스패치는 이 스탬프와 그 사이클에 선정된 LLM의 결정적 매칭이며, `manual` 판정 항목은
`-manual`로 rename된다.
_Avoid_: 무인 적격, 난이도, 우선순위

**유효 잔여율**:
유료로 분류된 래퍼 하나의 5시간 쿼터 잔여율과 주간 쿼터 잔여율 중 작은 값.
LLM 선정은 이 값 하나로 판단한다: 유효 잔여율 50% 이상인 유료 래퍼만 적격이고, 적격이
여럿이면 유효 잔여율이 큰 쪽(동률이면 `AUTOQAFIX_WRAPPERS` 목록의 앞쪽)을 쓴다. 유료가
모두 부적격이면 로컬 래퍼(`available`일 때만)를 쓰고, 그마저 불가하면 해당 주기의
LLM 작업을 건너뛴다.
_Avoid_: 남은 크레딧, 쿼터 비율

**작업 항목 파일 상태**:
`issues/` 안의 작업 항목(두 스트림 공통)은 파일명 접미사가 곧 상태다. 접미사 없음은 기계
검토 대상(해당 루프가 집어감), `-manual`은 agent-tier 판정이 사람 몫으로 이관한 것,
`-agent-failed`는 agent가 구현을 시도했다 실패해 대기 중인 것, `-later`는 사람이 미루어
둔 것(기계는 절대 보지 않음). 상태 전이는 rename으로 하고 commit·push하며, 번호는 접미사
불문 스트림 안에서 유일하다. 사람이 보강 후 접미사를 떼면 다시 기계 검토 대상이 된다.
_Avoid_: 태그, 라벨, 상태 필드

**실패 기록**:
autofix가 issue 구현에 실패했을 때 해당 issue 파일 안에 남기는 섹션(일시, 사용한 LLM,
실패 요지). 기록 후 파일은 `issue-#-agent-failed.md`로 rename된다. 재투입 시 실패 기록
섹션은 지우지 않고 이력으로 남겨 다음 시도의 맥락으로 쓴다.
_Avoid_: 에러 로그, 블랙리스트

**LLM 래퍼**:
`<provider>cli.{sh,ps1,bat}` 패밀리 — `claudecli` / `minimaxcli` / `qwencli` /
`codexcli` / `antigravitycli` / `deepseekcli`. 서로 다른 LLM CLI를 `-p PROMPT` 동일
인터페이스로 감싼 실행 스크립트로, `.claude/skills/autoqafix/wrappers/`에 번들되며
감싸는 실제 CLI(`claude`, `qwen` 등)는 PATH 전제다. 이름에 `cli`를 붙이는 이유는 감싸는
실행 파일과의 자기호출 충돌 방지다(예: `qwen.*` 금지). LLM 선정 로직의 산출물이 이 중
하나이며, 후보와 유료/로컬 분류는 env `AUTOQAFIX_WRAPPERS`가 선언한다. 각 래퍼의 응답
여부는 짝이 되는 `ping-<래퍼명>.*` 진단 스크립트로, 쿼터는 `usage-<래퍼명>.py`로 확인한다.
_Avoid_: qwen.{bat,ps1,sh}, LLM CLI, 에이전트 바이너리

**리뷰 사이클**:
`autotddreview` 스킬이 issue 하나에 대해 도는 4단계 — 구현(coder) → 리뷰(reviewer,
병렬) → 수정 계획(planner) → 재수정(re-fix). coder·planner·재수정은 항상 **실행 세션**
(스킬을 호출한 바로 그 모델·그 대화)이 인라인으로 담당하고, 리뷰어만 인자로 지정한다.
coder를 바꾸는 방법은 플래그가 아니라 다른 모델의 세션에서 스킬을 실행하는 것이다.
_Avoid_: 구 스킬명, 멀티모델 루프, --coder/--planner 플래그

**셀프 리뷰**:
리뷰 사이클에서 리뷰어를 지정하지 않았을 때의 기본값. 실행 세션과 같은 모델이 구현
기억이 없는 새 컨텍스트(서브에이전트)에서 코드만 보고 수행하는 리뷰. 같은 대화에서
이어서 하는 자기 검토가 아니다. 산출 파일명의 리뷰어 자리는 `self`로 고정한다.
_Avoid_: 자기 검토, 자체 리뷰

**승격률**:
리뷰어 평가의 정본 지표 — 리뷰어가 낸 finding 중 플래너(기계)가 must-fix 또는
good-to-fix로 승격한 비율. 플래너의 판정(증거 게이트 + must-fix 재검증)이 기준이며,
파킹된 good-to-fix를 사람이 나중에 승격했는지/방치했는지는 이 지표에 반영하지 않는다
— 사람 판단은 드물고 느려 표본이 되지 못하므로 의도적으로 제외한 것이다.
_Avoid_: 수용률, 최종 수용률, 사람 승인율

**worktree 격리**:
자동화 루프의 agent(autoqa, autofix, autodev)는 항상 일회용 git worktree에서 작업하고,
사람은 main tree에서 작업한다는 규칙. agent의 실패 처리는 worktree 폐기로 끝나며 main
tree의 사람 작업물은 어떤 경우에도 건드리지 않는다. agent 간 동시 실행은 worktree가 아닌
별도 뮤텍스로 직렬화한다.
_Avoid_: 브랜치 격리, 샌드박스
