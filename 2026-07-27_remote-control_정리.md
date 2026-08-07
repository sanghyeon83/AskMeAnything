# Remote Control 설정 및 이중화 작업 준비 정리

> 작성일: 2026-07-27 / 최종 갱신: 2026-08-06 / Question 세션 대화 내용 정리

## 1. 이중화 작업 폴더 결정

- 문자발송시스템 두 프로젝트(`D:\workspace\Tokbell`, `D:\workspace\tokbell_sender`)의 이중화 작업을 진행하기로 함
- 작업 폴더명: **`D:\test_workspace\tokbell_ha`**
  - `ha` = High Availability(고가용성), 이중화 작업의 표준 표기
  - 한글 폴더명은 일부 빌드 도구와 충돌 가능해 제외

## 2. 최종 구성: 백그라운드 자동 실행 ✅

**이제 파워셸/터미널 창 없이 동작한다.**

- 시작프로그램 스크립트: `C:\Users\sanghyeon\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\claude-remote-control.vbs`
- PC를 켜고 로그인하면 **20초 후 9개 세션이 전부 창 없이 백그라운드로 자동 실행**됨
- 태블릿 접속: 창이 없어 QR은 안 뜨므로, Claude 앱 **세션 목록에서 이름으로 선택**해 접속
  - 재부팅하면 세션이 새로 발급되므로 목록에서 **가장 최신** 세션을 선택할 것
  - ⚠️ Code 탭의 컴퓨터 아이콘은 매번 새 세션을 만드니 사용하지 말 것

### 자동 실행되는 9개 세션 (2026-08-06 기준)

| 폴더 | 태블릿 표시 이름 |
|---|---|
| D:\test_workspace\question | Question |
| D:\test_workspace\tokbell_ha | Tokbell HA |
| D:\workspace\morning_economy | Morning Economy |
| D:\workspace\Tokbell | Tokbell |
| D:\workspace\tokbell_sender | Tokbell Sender |
| D:\workspace\rabbit-typing-adventure | Rabbit Typing |
| D:\workspace\webs.madang.ai | Webs Madang |
| D:\workspace\kafka_test | kafka test_로컬 |
| D:\test_workspace\AskMeAnything | AskMeAnything |

### 재부팅하면 데이터가 날아가나? → 아니오

- 작업 파일, 메모리, **지난 대화 기록 전부 PC 디스크에 보존**됨
  - 대화 기록 위치: `C:\Users\sanghyeon\.claude\projects\<인코딩된 폴더경로>\*.jsonl`
- 다만 `claude remote-control`은 기본값이 **빈 대화로 새로 시작**이라, 그냥 두면 이어지지 않음
- 이어받기 옵션: `-c`(`--continue`) = 그 폴더의 마지막 대화 이어받기 / `--session-id <id>` = 특정 대화 지정

**폴더별 적용 (2026-08-06 갱신)**

| 폴더 | 이어받기 | 이유 |
|---|---|---|
| Question | ✅ `-c` | 2026-08-06에 미적용 → `-c`로 변경 (특정 대화 고정은 아래 이유로 불가) |
| Tokbell HA | ✅ `-c` | 이중화 작업이 여러 날 이어짐 |
| Tokbell | ✅ `-c` | 개발 프로젝트, 맥락 유지 이득 |
| Tokbell Sender | ✅ `-c` | 개발 프로젝트, 맥락 유지 이득 |
| Rabbit Typing | ✅ `-c` | 개발 프로젝트, 맥락 유지 이득 |
| Webs Madang | ✅ `-c` | 개발 프로젝트, 맥락 유지 이득 |
| kafka test_로컬 | ✅ `-c` | 개발 프로젝트, 맥락 유지 이득 |
| AskMeAnything | ✅ `-c` | 2026-08-06 등록, 개발 프로젝트 |
| Morning Economy | ❌ | 매일 새로 발행하는 반복 작업 |

> `-c`는 맥락이 유지되는 대신 긴 대화를 계속 물고 가서 사용량(5시간/주간 한도) 소진이 빨라짐. 그래서 전부가 아니라 선별 적용.

### ⚠️ `-c`의 함정과 폴백 처리 (2026-08-06 추가)

`-c`는 **이어받을 "최근" 대화가 없으면 세션을 띄우지 않고 즉시 종료**한다.

```
Error: No recent session found in this directory or its worktrees.
```

며칠간 안 쓴 폴더는 이 조건에 걸린다. 창이 없는 백그라운드 실행이라 **에러가 화면에 안 보이고, 태블릿 목록에서 그 세션만 조용히 사라진다.**

→ 그래서 `.vbs`의 `RunRC`가 **`-c` 실패 시 빈 대화로 자동 폴백**하도록 수정함. 이어받기가 되면 되는 대로, 안 되면 최소한 세션은 뜬다.

```
claude remote-control -c --name '이름'; if ($LASTEXITCODE -ne 0) { claude remote-control --name '이름' }
```

> 참고: 특정 대화를 콕 집어 이어받으려면 `--session-id <id>`를 쓴다. 폴백으로 새 대화가 뜬 뒤에는 그 빈 대화가 "최근 대화"가 되므로, 다음번 `-c`는 원래 작업이 아니라 그 빈 대화를 물게 된다.

### 세션 추가/제거

- `.vbs` 파일 안의 `RunRC "폴더경로", "표시이름", "이어받기옵션"` 줄을 추가/삭제
  - 세 번째 인자는 **문자열**이다 (2026-08-06에 True/False → 문자열로 변경)

  | 값 | 동작 |
  |---|---|
  | `""` | 매번 빈 대화로 새로 시작 |
  | `"-c"` | 그 폴더의 마지막 대화 이어받기 |
  | `"--session-id <ID>"` | 특정 대화를 지정해 항상 그것만 이어받기 |

  - `""`가 아닌 경우 실패 시 자동으로 새 대화 폴백이 걸린다
- 이전 버전은 `claude-remote-control.vbs.bak`으로 백업해 둠
- 수동으로 전체 재시작하려면: 기존 프로세스 종료 후 `wscript.exe "<.vbs 경로>"` 실행
- 실행 중인지 확인:
  ```powershell
  Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Where-Object { $_.CommandLine -match 'remote-control' } | Select-Object ProcessId, @{N='Cmd';E={$_.CommandLine}}
  ```

## 3. 새 프로젝트 등록 절차 (앞으로의 방식)

1. 새 터미널에서 폴더로 이동 → `claude` 실행 → 신뢰(trust) 확인 Yes → `/exit`
   - ⚠️ **절대 건너뛰지 말 것.** 이 단계 없이 `.vbs`에만 추가하면 백그라운드에서 아래 에러로 조용히 죽는다.
     `Error: Workspace not trusted. Please run 'claude' in <폴더> first...`
   - PowerShell에서는 `cd <폴더>; claude` (PowerShell 5.1에는 `&&`가 없고 `cd /d`도 안 먹는다)
2. `claude remote-control --name "<이름>"` 실행 → **QR 표시된 상태로 태블릿에서 접속해 확인(OK)**
3. OK가 확인되면 → 터미널 세션을 종료하고 **백그라운드 방식으로 전환** + `.vbs`에 추가해 자동 시작에 포함

## 4. 오늘 겪은 문제와 원인 (트러블슈팅 기록)

| 증상 | 원인 | 해결 |
|---|---|---|
| 태블릿에서 질문하면 "생각 중"만 뜨고 답변 없음 | PC 쪽 remote-control 프로세스가 죽어 있었음 (태블릿은 리모컨일 뿐) | 프로세스 재실행 후 새 세션으로 재접속 |
| `remote-control : The term is not recognized` 오류 | `claude`를 빼고 입력함 | 전체 명령은 `claude remote-control --name "이름"` |
| 세션이 자꾸 죽음 | Claude 작업 셸(샌드박스) 안에서 띄워 셸 정리 시 함께 종료됨 + QR 탭에 키 입력(Ctrl+C 등)하면 종료됨 | 독립 프로세스로 실행 → 최종적으로 백그라운드 상시 실행으로 전환 |
| 이름 없는 정체불명 remote-control 프로세스 | 이전에 이름 없이 실행했던 잔여 세션 | 종료 처리함 |

### 2026-08-06 추가 (태블릿에 Tokbell / kafka 두 세션이 안 보임)

`.vbs`에 8개가 등록돼 있는데 **6개만 떠 있었다.** 창이 없어서 죽은 걸 몰랐고, 원인은 서로 달랐다.

| 세션 | 원인 | 해결 |
|---|---|---|
| Tokbell | `-c` 이어받기 실패 — 마지막 대화가 07-28이라 "최근 대화" 범위 밖 (`No recent session found`) | `.vbs`에 `-c` 실패 시 새 대화 폴백 추가 |
| kafka test_로컬 | 워크스페이스 신뢰(trust) 미완료 — 등록 절차 1단계를 건너뛰고 `.vbs`에만 추가했음 (`Workspace not trusted`) | 해당 폴더에서 `claude` 한 번 실행해 trust 승인 |

**진단 방법**: 백그라운드라 에러가 안 보이므로, 출력을 파일로 받아서 확인한다.

```powershell
Start-Process -FilePath "C:\Users\sanghyeon\.local\bin\claude.exe" `
  -ArgumentList 'remote-control -c --name "이름"' -WorkingDirectory '폴더경로' `
  -RedirectStandardOutput "$env:TEMP\rc.out.log" -RedirectStandardError "$env:TEMP\rc.err.log" `
  -WindowStyle Hidden
```

몇 초 뒤 `rc.err.log`를 보면 죽은 이유가 그대로 찍혀 있다.

> 부수 교훈: `.vbs`를 열어볼 때 **파일 인코딩이 UTF-16LE(BOM `FF FE`)**임에 주의. 잘못된 인코딩으로 읽으면 한글 이름이 깨져 보이고, 실제로 이번에 표시 이름을 `kafka test_웹`으로 잘못 읽어 엉뚱한 이름의 세션을 띄웠다가 되돌렸다. 수정 시에도 UTF-16LE로 저장해야 한다.

### 2026-08-06 추가 (AskMeAnything 등록 — trust 판정 함정)

`~/.claude.json`의 프로젝트 항목에 `hasTrustDialogAccepted: true`가 **있어도** CLI가 `Workspace not trusted`로 거부할 수 있다. 그 값은 데스크톱 앱이 기록한 것으로, CLI의 trust 판정과 별개다 (반대로 Tokbell은 항목이 아예 없는데도 통과). **설정 파일을 보고 trust 여부를 판단하지 말고, 등록 절차 1단계(그 폴더에서 인터랙티브 `claude` 실행 → Yes → `/exit`)를 무조건 수행할 것.**

등록을 창에서 직접 할 때는 이전과 동일한 두 줄이면 된다 (QR이 바로 떠서 태블릿 확인이 쉬움. 단, 창을 닫으면 세션도 꺼지므로 상시 운용은 `.vbs` 백그라운드 방식):

```powershell
cd <폴더>; claude          # trust Yes → /exit
claude remote-control -c --name '이름'
```

### ⚠️ 2026-08-06 추가 — 데스크톱 앱 대화는 태블릿에서 이어받을 수 없다

`question` 폴더에 활성 대화가 여러 개 생겼다 (데스크톱 앱 1개 + remote-control이 만든 것들). **이걸 하나로 합치려 시도했으나 불가능한 것으로 확인됐다.**

**확인된 사실 (실제 시도해서 얻은 결과)**

| 시도 | 결과 |
|---|---|
| `--session-id <로컬 UUID>` | ❌ 실패. `Error: Could not reach the server to look up session ...` — 이 옵션은 **클라우드 세션 ID(`session_...`)** 만 조회한다. 로컬 `.jsonl` 파일명 UUID는 서버가 모른다 |
| `-c` | ⚠️ 로컬 최신 대화가 아니라 **remote-control이 관리하던 마지막 세션**을 이어받는다 (`Resuming session session_...`) |

**결론: 데스크톱 앱(또는 `/remote-control`을 못 쓰는 환경)에서 진행한 대화는 태블릿으로 넘길 수 없다.** remote-control이 다루는 세션과 별개의 계보다.

### ✅ 해결법 — 로컬 대화를 태블릿에 올리는 방법 (2026-08-06 성공)

**`remote-control` 하위 명령이 아니라, `claude`의 `--remote-control` 옵션을 쓴다.** 이건 `--resume`과 조합할 수 있어서 로컬 대화를 그대로 원격 세션으로 띄운다.

```powershell
cd D:\test_workspace\question; claude --resume <로컬-세션-UUID> --fork-session --remote-control "Question"
```

| 옵션 | 역할 |
|---|---|
| `--resume <UUID>` | 로컬 `.jsonl` 대화를 이어받는다 (하위 명령의 `--session-id`와 달리 **로컬 UUID가 먹는다**) |
| `--fork-session` | 새 세션 ID로 복사해서 띄운다. 원본이 데스크톱 앱에서 살아있을 때 **충돌을 피하려면 필수** |
| `--remote-control "이름"` | 그 세션을 태블릿에 노출 |

### 🔑 결정적 함정 — 출력 리다이렉트를 걸면 죽는다

`claude --remote-control`은 **대화형 세션**이라 표준입출력이 파일로 묶이면 즉시 종료된다. `-WindowStyle Hidden`은 문제없다.

```powershell
# ❌ 죽는다 — Redirect 때문 (창 숨김 때문이 아니다)
Start-Process ... -RedirectStandardOutput a.log -RedirectStandardError b.log -WindowStyle Hidden
#   → Error: No deferred tool marker found in the resumed session. ... Provide a prompt to continue.

# ✅ 산다 — 리다이렉트만 빼면 창 없이 정상 상주
Start-Process -FilePath "C:\Users\sanghyeon\.local\bin\claude.exe" `
  -ArgumentList '--resume <UUID> --remote-control "Question"' `
  -WorkingDirectory 'D:\test_workspace\question' -WindowStyle Hidden
```

> 백그라운드 세션을 진단할 때 쓰는 `-RedirectStandardError` 기법(위 4장 참고)은 **`remote-control` 하위 명령에만** 쓸 것. `--remote-control` 옵션 형태에 걸면 진단하려던 그 프로세스를 자기가 죽인다.

**최종 절차 (2026-08-06 확정)**

```powershell
# 1) 포크 생성 — 원본이 데스크톱 앱에서 살아있으므로 --fork-session 필수
#    (초기 프롬프트를 주면 한 번 응답 후 종료되지만, 그 과정에서 포크 .jsonl이 만들어진다)
Start-Process -FilePath "C:\Users\sanghyeon\.local\bin\claude.exe" `
  -ArgumentList '--resume <원본UUID> --fork-session --remote-control "Question" "연결 확인용"' `
  -WorkingDirectory 'D:\test_workspace\question' -WindowStyle Hidden
#    → 새로 생긴 .jsonl 파일명이 포크된 대화의 UUID

# 2) 그 포크를 창 없이 상주시킨다 (리다이렉트 금지)
Start-Process -FilePath "C:\Users\sanghyeon\.local\bin\claude.exe" `
  -ArgumentList '--resume <포크UUID> --remote-control "Question"' `
  -WorkingDirectory 'D:\test_workspace\question' -WindowStyle Hidden

# 3) .vbs의 Question 줄을 "--resume <포크UUID>"로 바꿔 재부팅 후에도 유지
```

**`-c`는 이 대화를 못 찾아간다.** `-c`는 remote-control 계보의 마지막 클라우드 세션을 물기 때문에, 포크된 로컬 대화가 아니라 엉뚱한 예전 세션을 잡는다. 그래서 Question만 `--resume`으로 대화를 직접 지정하는 방식을 쓴다.

**그 외 대응**

- 태블릿에서 이어갈 작업은 **처음부터 remote-control 세션에서** 진행하는 게 가장 깔끔하다
- 넘겨야 할 때는 **인수인계 파일**(이 문서처럼)을 폴더에 남겨도 된다
- 터미널 세션이라면 그 안에서 `/remote-control` 입력으로도 된다 (데스크톱 앱에서는 이 명령을 못 쓴다)
- 포크한 순간부터 원본(데스크톱)과 사본(태블릿)은 **각자 갈라진다.** 한쪽만 쓰는 게 헷갈리지 않는다

## 5. 운영 주의사항

- 재실행/재부팅 때마다 세션 URL이 새로 발급됨 → 태블릿은 항상 세션 목록의 최신 세션으로
- 9개 세션이 상시 대기 중 — 실제 사용량은 대화한 만큼 소진되지만, 안 쓰는 프로젝트는 `.vbs`에서 빼는 것도 방법 (`/usage`로 확인)
- **가끔 실제로 몇 개가 떠 있는지 확인할 것.** 위 확인 명령의 결과 개수가 `.vbs`의 `RunRC` 줄 개수(현재 9)와 맞아야 한다. 모자라면 위 진단 방법으로 원인을 본다.
- 클라우드 세션(claude.ai/code)은 Linux VM이라 로컬 Chrome/티스토리/스케줄러가 필요한 작업(morning_economy 발행 등)은 불가 → Remote Control 방식 유지
