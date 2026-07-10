# issue-6: ping 진단 스크립트 18종

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

`regression-tests/verify-issue-6.sh` 작성: 위 시나리오를 fake-wrapper로 자동화.
실 래퍼 호출(크레딧) 금지.
