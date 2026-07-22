# issue-51: aacpd deploy 단계 — deploy-to-{env}.sh를 deploy.sh보다 우선 탐색
agent-tier: any

## 배경

apiproxy-project(이 스킬 세트를 쓰는 대상 프로젝트 중 하나)에서 `deploy-to-prod.sh`/
`deploy-to-dev.sh`처럼 환경별로 파일을 분리한 배포 스크립트를 만들었는데, 현재
`aacpd/aacp.sh`(및 `.ps1`)의 deploy 탐색은 `deploy.sh` → `deploy-to-env.sh`
(둘 다 `--env <env>` 인자를 받는 단일 스크립트 형태) 순서로만 찾도록 되어 있어
이 파일들을 전혀 인식하지 못했다. 사용자 확인 결과, 대상 프로젝트가 환경별로
파일을 나눠 `deploy-to-<env>.sh`(예: `deploy-to-dev.sh`, `deploy-to-prod.sh`)를
두는 경우 그 파일이 존재하면 **인자 없이 그 자체를 바로 호출**하고, 없을 때만
기존 `deploy.sh --env <env>`로 폴백해야 한다.

**`deploy-to-env.sh`(단일 파일, `--env` 인자로 환경 분기)는 오타였다** — 사용자가
실제로 만들거나 쓴 적이 없는 관례이며, 스킬 문서에만 존재하던 잘못된 옵션이었다.
이번 이슈에서 이 관례에 대한 언급을 스킬 문서·스크립트에서 전부 제거한다
(하위 호환으로 남길 대상 자체가 아니다 — 애초에 쓰인 적이 없다).

## 요구사항

### 1. `aacpd/aacp.sh` (및 `.ps1`) deploy 탐색 순서 변경

우선순위(숫자가 낮을수록 우선):

1. `deploy-to-<env>.sh` (예: `--env dev`면 `deploy-to-dev.sh`, `--env prod`면
   `deploy-to-prod.sh`) — **존재하면 인자 없이 그대로 실행**. 이 파일은 이미
   특정 환경 전용이므로 `--env` 인자를 받지 않는다.
2. 없으면 `deploy.sh --env <env>` — 기존과 동일, 인자로 환경을 넘긴다.
3. 그것도 없으면 기존과 동일하게 "no deploy script found" 메시지 후 skip(실패
   아님).

`deploy-to-env.sh` 탐색 분기 자체를 코드에서 제거한다(오타였으므로 하위 호환
유지 대상이 아님).

### 2. `aacpd/SKILL.md` 문서 갱신

- "What the script does" 6번(Deploy) 절의 탐색 순서를 위 2단계 우선순위로 갱신.
- "A naming note" 절의 표(대상 repo 쪽 파일 목록)에서 `deploy-to-env.sh` 언급을
  삭제하고, `deploy-to-<env>.sh`(환경별 분리, 인자 없음)를 `deploy.sh`와 나란히
  추가해 둘의 차이(인자를 받는지, 우선순위)를 설명한다.
- Gotchas 절의 "target repo's deploy script" 설명에서도 `deploy-to-env.sh`
  언급을 전부 제거하고 새 우선순위를 반영한다.
- `deploy-to-env.sh`라는 문자열이 `aacpd/SKILL.md`, `aacp.sh`, `aacp.ps1`,
  `aacp.bat` 어디에도 남지 않아야 한다.

## 하지 말 것

- `deploy-to-env.sh`를 하위 호환으로 남기는 것 — 오타였으므로 완전히 제거한다.
- qa/prod 배포 로직 변경 — 이 스킬은 여전히 dev에만 배포한다(`--env dev` 고정).
  `--env` 인자 자체의 의미나 호출 범위는 바뀌지 않는다.

## 승인 기준

- [ ] `deploy-to-dev.sh`만 있는 대상 repo에서 `aacp.sh <issue> ...`(dev 배포)
      실행 시 `deploy-to-dev.sh`가 인자 없이 호출됨(`deploy.sh`는 호출되지 않음).
- [ ] `deploy-to-dev.sh`와 `deploy.sh`가 둘 다 있는 대상 repo에서
      `deploy-to-dev.sh`가 우선 호출됨.
- [ ] `deploy.sh`만 있는 대상 repo는 기존과 동일하게 `deploy.sh --env dev` 호출.
- [ ] 아무 배포 스크립트도 없으면 기존과 동일하게 skip(exit 0, 안내 메시지).
- [ ] `aacp.ps1`도 동일한 2단계 우선순위로 갱신(Gotchas에 명시된 대로 수동 이식,
      실제 PowerShell 환경에서 실행 검증은 이 저장소 환경 제약상 불가하므로
      코드 리뷰로 대체 — 기존 관례와 동일).
- [ ] `aacpd/SKILL.md`가 새 2단계 우선순위를 정확히 반영하고, `deploy-to-env.sh`
      문자열이 스킬 디렉토리(`aacp.sh`/`aacp.ps1`/`aacp.bat`/`SKILL.md`) 어디에도
      남아있지 않음.

## 검증

`regression-tests/verify-issue-51.sh`(신규): 임시 git repo 픽스처로 다음을
확인한다.
- `deploy-to-dev.sh`만 있음 → 그것만 호출됨(더미 스크립트가 자신의 이름을
  마커 파일에 기록해 확인).
- `deploy-to-dev.sh`+`deploy.sh` 둘 다 있음 → `deploy-to-dev.sh`만 호출됨.
- `deploy.sh`만 있음 → `deploy.sh --env dev`로 호출됨(인자 전달 확인).
- 아무것도 없음 → skip, exit 0.
- `grep -rL deploy-to-env.sh skills/aacpd/`로 해당 문자열이 스킬 디렉토리 어디에도
  없음을 단언.

## 구현 결과

- **구현 완료 일시**: 2026-07-22T03:18:53-04:00
- **변경 파일**:
  - `skills/aacpd/aacp.sh` — deploy 탐색을 `deploy-to-dev.sh`(인자 없음, 우선) →
    `deploy.sh --env dev` 2단계로 변경. `deploy-to-env.sh` 분기 제거.
  - `skills/aacpd/aacp.ps1` — 동일하게 수동 이식(`deploy-to-dev.ps1` 우선,
    `deploy-to-env.ps1` 분기 제거). 실제 PowerShell 실행 검증은 환경 제약상 불가.
  - `skills/aacpd/SKILL.md` — "A naming note", "What the script does" 6번,
    Gotchas의 deploy 관련 서술을 새 2단계 우선순위로 갱신, `deploy-to-env` 문구 삭제.
  - `README.md` — 스킬 설명, Quickstart, Conventions 절의 deploy 관련 서술 갱신,
    `deploy-to-env` 문구 삭제.
  - `skills/autoqafix/autoqafix-doctor.py` — `check_deploy()` docstring에서
    "스펙의 deploy-to-env" 표현 제거(글로직 자체는 이미 `deploy-to-*{ext}` 일반
    패턴이라 변경 불필요, 설명 문구만 정정).
  - `regression-tests/verify-issue-51.sh` (신규) — 임시 git repo 픽스처 4종으로
    우선순위/인자 전달/skip 동작 검증 + `deploy-to-env` 문자열 부재 단언.
  - `issues/issue-51.md` — 본 파일.
- **계획 대비 편차**: 없음.
- **검증 결과**: `bash regression-tests/verify-issue-51.sh` 전체 PASS. 전체 회귀
  스위트 중 10개(21/22/26/33/34/38/39/41/47/48)가 실패하지만, `git stash`로
  이번 변경을 제거한 베이스라인에서도 동일하게 실패함을 확인 — 이번 변경과
  무관한 기존 실패(issue-50에서도 동일하게 보고된 것과 일치). `pyproject.toml`이
  저장소 루트에 없어 tdd2 규약에 따라 ruff/pyright 게이트는 자동 skip.
