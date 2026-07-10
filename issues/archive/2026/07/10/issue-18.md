# issue-18: autoqafix 1회형 + autoqafix-loop
agent-tier: paid-only

## 배경

production 주력. qa→fix를 1회씩 돌리는 합성 1회형과, 부팅 자동 실행용 루프.
명세: `docs/autoqafix-design.md`의 "루프".

## 요구사항

1. `.claude/skills/autoqafix/autoqafix.py` (PEP-723): autoqa 1회 → autofix 1회 순차 실행
   (각각 exit code 존중, qa 실패해도 fix는 시도). `FIXED=<n>`을 그대로 전파
2. `.claude/skills/autoqafix/autoqafix-loop.py` (PEP-723):
   - 시작 시 `AUTOQAFIX_BOOT_WAIT`(기본 180초) 대기
   - 무한 루프: 페이즈별 최소 간격 검사 → autoqafix 1회형 실행 → 대기.
     페이즈별 마지막 실행 시각을 `state_dir()/phase-times.json`에 기록,
     `AUTOQAFIX_INTERVAL`(기본 21600초=6시간) 미달 페이즈는 건너뜀.
     라운드 간 대기는 60초 단위 폴링(간격 도달 검사)
   - `--reboot-on-fix`: 라운드의 `FIXED` ≥ 1이면 재시동. 재시동 이력을
     `state_dir()/reboots.json`에 기록, 최근 24시간 내 `AUTOQAFIX_MAX_REBOOTS_24H`
     (기본 4) 초과 시 "reboot 보류(폭주 가드)" 경고만 출력하고 루프 지속.
     재시동 명령은 `SHUTDOWN_CMD`(기본: Windows `shutdown /r /t 60`,
     POSIX `sudo shutdown -r +1`)
   - `--interval <초>`, `--boot-wait <초>` CLI 인자로 env 대체 가능
3. repo 루트에 `autoqafix.{sh,ps1,bat}`, `autoqafix-loop.{sh,ps1,bat}` 런처
   (issue-14 패턴, `.bat` pause 포함)

## 승인 기준

시간 조작은 전부 env/인자로 (실제 6시간 대기 금지):

- [ ] `--boot-wait 1 --interval 2`로 루프를 백그라운드 실행, fake 페이즈(env로
      autoqa/autofix를 무해한 fake로 대체 가능하게 — `AUTOQAFIX_QA_CMD`/
      `AUTOQAFIX_FIX_CMD` 주입점을 둘 것) 2라운드 후 kill → phase-times.json에
      두 페이즈 기록 존재
- [ ] `AUTOQAFIX_FIX_CMD`가 `FIXED=1`을 출력 + `--reboot-on-fix` +
      `SHUTDOWN_CMD="echo REBOOT"` → 출력에 `REBOOT` 등장
- [ ] reboots.json에 최근 24시간 4건을 미리 심으면 `REBOOT` 대신 폭주 가드 경고
- [ ] interval 미달 시 페이즈가 실행되지 않는다 (fake 호출 로그로 확인)

## 검증

`regression-tests/verify-issue-18.sh` 작성: 위 전부. sleep 최소화(총 30초 이내).
