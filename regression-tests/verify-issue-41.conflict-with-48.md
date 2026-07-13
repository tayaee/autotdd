# verify-issue-41.sh ↔ issue-48 충돌 문서

## 무엇이 바뀌었나

`verify-issue-41.sh`는 issue-41(autotddreview 파생 이슈 생성)이 도입한
SKILL.md 형식을 단언한다. 그중 한 단언:

```bash
has "-fixing-<N>" "파생 이슈 파일명 -fixing-<N>"
```

issue-48(finding 슬러그 + BY 추가)이 fixing 파생 형식을
`fixing-<원본>-<finding-slug>`로 확장하면서, SKILL.md에서 옛 `-fixing-<N>`
단독 패턴이 사라졌다. 단언을 일반화:

```bash
has "-fixing-<" "파생 이슈 파일명 -fixing-<N> (이전) 또는 -fixing-<N>-<slug> (확장)"
```

prefix 매치로 옛/신 양쪽을 모두 포함한다. 옛 형식 자체는
`docs/spec/spec-issue-filenames.md`의 "레거시 불변" 정책에 따라
archive에 그대로 남지만, **새로 작성되는** SKILL.md/SPEC에는 등장하지
않는다 — 따라서 옛 형식만 단언하는 것은 미래 회귀다.

## 사람 검토 요청 사항

없음. 단언의 의도(파생 이슈 파일명이 `-fixing-<` prefix를 가진다)는
보존되었고, 패턴만 일반화됐다. 사람 결정 필요한 변경이 아니다.

## 영향 범위

- `verify-issue-41.sh` 한 단언만 변경
- 다른 모든 단언, 다른 스크립트는 영향 없음