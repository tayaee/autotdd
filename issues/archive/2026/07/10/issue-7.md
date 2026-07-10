# issue-7: ping 진단 스크립트 18종
agent-tier: local-ok

## 배경

래퍼 6종이 실제로 응답하는지 사람이 확인하는 진단 도구. 설치 직후·장애 시 수동
실행용이며 루프의 preflight에는 포함되지 않는다(크레딧 소모 방지).

## 요구사항

1. `.claude/skills/autoqafix/wrappers/`에 래퍼 6종(claudecli/minimaxcli/qwencli/
   codexcli/antigravitycli/deepseekcli) 각각의 `ping-<래퍼명>.{sh,ps1,bat}` 작성
   (18개 파일)
2. 동작: 같은 디렉토리의 해당 래퍼를 `-p "respond with exactly: pong"`으로 호출,
   타임아웃 120초(env `PING_TIMEOUT`으로 대체 가능)
3. 성공(exit 0 + 출력에 `pong` 포함): `OK <래퍼명> (<경과 초>s)` 출력, exit 0
4. 실패 시 exit 1 + 원인별 안내:
   - 래퍼 파일 없음 → `[원인] <래퍼> 없음` `[조치] autotdd 설치 확인`
   - 타임아웃 → `[원인] <T>초 내 무응답` `[조치] 네트워크/서비스 상태, 쿼터 확인
     (claude: claude.ai, qwen: 로컬 서비스 기동 여부)`
   - 비정상 종료/pong 불포함 → `[원인] 응답 이상 (exit=<N>)` `[조치] <래퍼> 단독
     실행으로 에러 메시지 확인`
5. `.sh`는 래퍼 경로를 env `PING_WRAPPER`로 대체 가능하게(테스트 주입점)

## 승인 기준

- [ ] `PING_WRAPPER=fake-wrapper.sh`(FAKE_MODE=ok, 출력 pong)로 `ping-claudecli.sh`
      → `OK` 출력, exit 0
- [ ] FAKE_MODE=hang + PING_TIMEOUT=2 → 2초 부근에 exit 1 + 타임아웃 안내
- [ ] FAKE_MODE=fail → exit 1 + `[원인]`/`[조치]` 출력
- [ ] 18개 파일 모두 존재, `.sh` 6개는 `bash -n` 통과

## 검증

`regression-tests/verify-issue-7.sh` 작성: 위 시나리오를 fake-wrapper로 자동화.
실 래퍼 호출(크레딧) 금지.

## 구현 결과

**구현 완료 일시**: 2026-07-10T18:03:13-0400

**변경 파일**:
- `.claude/skills/autoqafix/wrappers/ping-{claudecli,minimaxcli,qwencli,codexcli,antigravitycli,deepseekcli}.{sh,ps1,bat}` (신규, 18개)
- `regression-tests/verify-issue-7.sh` (신규)

**계획 대비 편차**: `.bat`은 배치의 프로세스 타임아웃/kill 기능 부재로
자체 구현 대신 `ping-<name>.ps1`로 위임하는 얇은 디스패처로 작성했다
(`aacp.bat` → `aacp.ps1` 위임과 동일한 패턴, 기존 코드베이스 컨벤션 재사용).
`.ps1`은 `Start-Job`/`Wait-Job`으로 타임아웃을 구현했다(PowerShell 표준
패턴). 승인 기준의 시나리오 4개는 모두 `ping-claudecli.sh`로 대표 검증했고,
나머지 5개 래퍼는 `PING_WRAPPER` 주입으로 OK 경로만 추가 확인했다(동일
템플릿에서 이름만 다르므로 나머지 3개 실패 시나리오는 중복 검증으로 판단해
생략).

**검증 결과**: `regression-tests/verify-issue-7.sh` 단독 실행 exit 0(승인
기준 전부 PASS, 6개 래퍼 모두 OK 경로 확인). `run-regression-tests`로
issue-3+4+5+6+7 전체 실행 결과 PASS=5 FAIL=0. Python 프로젝트가 아니므로
(`pyproject.toml` 없음) ruff/pyright/pytest 단계는 해당 없음. `.ps1`/`.bat`은
이 환경에 PowerShell이 없어 실행 검증 불가 — 존재 확인만 함(주석에도 명시).
