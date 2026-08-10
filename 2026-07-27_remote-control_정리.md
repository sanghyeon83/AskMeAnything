# Claude Remote Control 운영 가이드

> 최종 갱신: 2026-08-10 (전면 재작성 — 이전 기록은 git 히스토리에 있음)
>
> 목표: **PC를 재부팅해도 태블릿에서 대화가 끊기지 않고 이어지는** 백그라운드 세션 운영.
> 2026-08-10에 8개 세션이 전부 빈 대화로 뜨는 사고를 겪고, 재발 방지 절차를 포함해 다시 정리했다.

---

## 1. 프로젝트 등록 방법 (AskMeAnything 예시)

새 프로젝트를 태블릿에서 쓰려면 아래 순서를 **그대로** 따른다. 순서를 건너뛰면 백그라운드에서 조용히 죽는다.

### 1단계. 폴더 신뢰(trust) 승인 — 절대 건너뛰지 말 것

```powershell
cd D:\test_workspace\AskMeAnything; claude
```

- trust 확인이 뜨면 **Yes** → `/exit`로 나온다
- 이 단계 없이 진행하면 `Error: Workspace not trusted`로 백그라운드에서 조용히 죽는다
- `~/.claude.json`에 `hasTrustDialogAccepted: true`가 있어도 믿지 말 것 — 그건 데스크톱 앱 기록이고 CLI 판정과 별개다. 무조건 이 단계를 실행한다
- PowerShell 5.1에는 `&&`가 없다. `cd <폴더>; claude` 형태로 쓴다

### 2단계. 창에서 띄워 태블릿 접속 확인

```powershell
claude remote-control -c --name "AskMeAnything"
```

- `-c` = 그 폴더의 마지막 대화 이어받기
- QR이 뜨면 태블릿에서 접속해 정상 동작을 확인한다
- **이어받을 최근 대화가 없으면 `-c`는 즉시 종료된다** (`Error: No recent session found ...`). 그럴 땐 처음 한 번은 빈 대화로 시작한다:

```powershell
claude remote-control --name "AskMeAnything"
```

### 3단계. 백그라운드 자동 실행에 등록

- 창을 닫고, `.vbs`(2장)에 `RunRC` 줄을 추가해 상시 백그라운드로 전환한다
- ⚠️ 창에서 직접 실행하는 세션은 **창을 닫으면 같이 죽는다.** 상시 운용은 반드시 `.vbs` 방식으로
- ⚠️ 이 명령들을 감싸는 래퍼 스크립트(.ps1 등)를 만들지 말 것. 등록 확인은 창에서 직접, 상시 운용은 `.vbs` — 두 가지로 통일한다

---

## 2. 백그라운드 자동 실행 + 재부팅 자동 복구

### 구조

- 시작프로그램 스크립트: `C:\Users\sanghyeon\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\claude-remote-control.vbs`
- PC를 켜고 로그인하면 대기 시간 후 **모든 세션이 창 없이 백그라운드로 자동 실행**된다
- 각 세션은 `-c` 이어받기를 시도하고, 실패하면 빈 대화로 폴백한다:

```
claude remote-control -c --name '이름'; if ($LASTEXITCODE -ne 0) { claude remote-control --name '이름' }
```

### ⚠️ 시작 대기 시간은 60~90초로 할 것 (2026-08-10 교훈)

- 원래 20초였는데, 08-10 재부팅에서 **8개 세션의 `-c`가 전부 실패해 전원 빈 대화로 떴다**
- `-c`는 클라우드 서버에서 이전 세션을 조회해야 하는데, 부팅 직후에는 네트워크가 아직 안 올라와 조회가 실패할 수 있다. 8개가 한꺼번에 죽은 것을 가장 잘 설명하는 원인이다
- **네트워크가 완전히 올라온 뒤에 실행되도록 대기 시간을 60~90초로 늘린다**

### `.vbs` 세션 추가/제거 규칙

- `RunRC "폴더경로", "표시이름", "이어받기옵션"` 줄을 추가/삭제한다
- 세 번째 인자는 **문자열**이다:

  | 값 | 동작 |
  |---|---|
  | `"-c"` | 마지막 대화 이어받기 (기본, 실패 시 빈 대화 폴백) |
  | `"--session-id <ID>"` | 특정 클라우드 세션(`session_...`)만 항상 이어받기 |
  | `""` | 매번 빈 대화로 새로 시작 |

- ⚠️ 파일 인코딩은 **UTF-16LE(BOM `FF FE`)**. 다른 인코딩으로 저장하면 한글 이름이 깨진다
- ⚠️ 수정 후에는 `RunRC` 줄 개수를 반드시 다시 센다. 줄이 조용히 누락된 사고가 있었다 (08-07 Question 줄)
- 수동 전체 재시작: 기존 claude 프로세스 종료 후 `wscript.exe "<.vbs 경로>"` 실행
- 실행 개수 확인:

```powershell
Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Where-Object { $_.CommandLine -match 'remote-control' } | Select-Object ProcessId, @{N='Cmd';E={$_.CommandLine}}
```

---

## 3. 재부팅 후 필수 확인 절차 — 이것 때문에 사고 난다

재부팅 후 세션이 **"떴는지"가 아니라 "이전 대화를 물고 왔는지"**를 확인해야 한다. 목록에 이름이 보여도 빈 폴백일 수 있고, **방치하면 복구 불가가 된다** (빈 세션이 "최근 대화"가 되어 다음 `-c`가 그걸 물기 때문).

### 30초 확인법

재부팅 후 태블릿에서 아무 세션이나 열고 **"우리가 지금까지 뭐 하고 있었지?"** 라고 물어본다.

- 기억한다 → 정상. 끝
- 기억 못 한다 → 폴백 발동. **즉시 4장 복구 절차로**

### 세션 ID로 판별하는 법

`-c` 이어받기가 **성공하면 기존 클라우드 세션 ID가 그대로 유지**되고 `updated_at`만 갱신된다. 실패(폴백)하면 새 ID가 발급된다.

| 신호 | 이어받기 성공 | 폴백(빈 대화) |
|---|---|---|
| 세션 ID | 기존 것 유지 | **새로 발급** |
| `created_at` vs `updated_at` | 다름 | **같음** |
| 누적 사용량 | 있음 | **0** |

---

## 4. 폴백 사고 복구 절차 (2026-08-10 실제 사례)

### 증상

재부팅 후 태블릿의 세션들이 전부/일부 빈 대화다.

### 복구 순서

1. **원인 로그부터 남긴다** (복구 먼저 하면 원인을 못 잡는다 — 08-10에 실제로 놓쳤다):

```powershell
Start-Process -FilePath "C:\Users\sanghyeon\.local\bin\claude.exe" `
  -ArgumentList 'remote-control -c --name "이름"' -WorkingDirectory '폴더경로' `
  -RedirectStandardOutput "$env:TEMP\rc.out.log" -RedirectStandardError "$env:TEMP\rc.err.log" `
  -WindowStyle Hidden
```

   몇 초 뒤 `rc.err.log`에 실패 사유가 그대로 찍힌다.
   (이 리다이렉트 기법은 `remote-control` 하위 명령에만 쓸 것 — `claude --remote-control` 옵션 형태는 대화형이라 즉시 죽는다)

2. **원본 세션을 찾는다**: 앱 세션 목록에서 재부팅 이전 날짜에 마지막으로 갱신된, 대화가 살아있는 세션을 확인한다

3. **빈 폴백 세션을 죽이고, 원본을 이어받아 다시 띄운다**: 폴백으로 뜬 프로세스를 종료하고, 필요하면 `--session-id <원본ID>`로 콕 집어 재기동한다

4. **빈 세션들을 목록에서 치운다**: 아카이브(또는 앱에서 삭제). 08-10에는 빈 1세대 7개(Tokbell HA / Tokbell / Tokbell Sender / Rabbit Typing / Webs Madang / Morning Economy / AskMeAnything)를 정리했다

### ⚠️ 복구하면 세션이 "두 세대"로 겹쳐 보인다

복구로 다시 띄우면 죽은 1세대와 새 2세대가 목록에 같은 이름으로 공존한다. **함정: 껍데기(1세대)가 정렬해 둔 프로젝트 그룹 자리에 앉고, 알맹이(2세대)는 "기타"로 밀린다.** 2세대는 폴더/브랜치 메타데이터를 아직 서버에 안 올려서 앱이 프로젝트를 못 알아보기 때문이다.

| | 1세대 (죽은 껍데기) | 2세대 (살아있는 알맹이) |
|---|---|---|
| 태그 | `remote-control-cli` | `remote-control-repl` |
| 앱 표시 위치 | 정렬된 프로젝트 그룹 | **기타** |
| 대화 | 비어 있음 | 이어져 있음 |

→ **정렬된 자리에 있다고 진짜가 아니다. 대화 내용으로 판단하고, 확인되면 껍데기를 정리한다.**
→ 08-10 확인 결과: **기타로 밀린 2세대가 진짜였고, 대화가 전부 이어져 있었다.** 세션 위치(그룹)는 이후 대화가 쌓이며 메타데이터가 올라가면 제자리를 찾는다

### 복구 중 주의

- **`.vbs` 수정은 한 곳에서만.** 08-10에 PC 세션과 클라우드 세션이 동시에 같은 문제를 보고 있었다. 파일 수정은 PC 쪽에서만 한다

---

## 5. 운영 원칙

- 태블릿에서 이어갈 작업은 **처음부터 remote-control 세션에서** 시작한다. 데스크톱 앱 대화는 remote-control로 넘길 수 없다 (계보가 다름 — `--session-id`는 클라우드 ID만 받고, 로컬 `.jsonl` UUID는 서버가 모른다)
- 넘겨야 할 상황이면 이 문서처럼 **인수인계 파일**을 폴더에 남긴다
- 재부팅 때마다 세션 URL이 새로 발급된다 → 태블릿은 항상 목록의 **최신** 세션으로 접속. Code 탭의 컴퓨터 아이콘은 매번 새 세션을 만드니 쓰지 말 것
- 대화 기록 원본은 PC 디스크에 있다: `C:\Users\sanghyeon\.claude\projects\<인코딩된 폴더경로>\*.jsonl` — 재부팅해도 파일은 안 사라진다. 사라지는 건 "연결"이지 "기록"이 아니다
- `-c`는 긴 대화를 계속 물고 가서 사용량(5시간/주간 한도) 소진이 빠르다. 안 쓰는 프로젝트는 `.vbs`에서 뺀다 (`/usage`로 확인)
- **가끔 실제 실행 개수를 확인한다**: 2장의 확인 명령 결과 개수 = `.vbs`의 `RunRC` 줄 개수여야 한다
- 클라우드 세션(claude.ai/code)은 Linux VM이라 로컬 Chrome/스케줄러가 필요한 작업은 불가 → 그런 프로젝트는 Remote Control 방식 유지

---

## 부록: 자주 만나는 에러

| 에러 | 원인 | 해결 |
|---|---|---|
| `Workspace not trusted` | 1장 1단계(trust)를 건너뜀 | 그 폴더에서 `claude` 실행 → Yes → `/exit` |
| `No recent session found in this directory or its worktrees.` | `-c`가 이어받을 최근 대화 없음 (오래 안 쓴 폴더, 또는 부팅 직후 네트워크 미완성) | 폴백으로 빈 대화가 뜸. 3장 확인 절차로 폴백 여부를 반드시 점검 |
| `Could not reach the server to look up session ...` | `--session-id`에 로컬 UUID를 넣음 | 클라우드 ID(`session_...`)만 유효 |
| `remote-control : The term is not recognized` | `claude`를 빼고 입력 | `claude remote-control --name "이름"` |
| 태블릿에서 "생각 중"만 뜨고 답 없음 | PC 쪽 프로세스가 죽어 있음 (태블릿은 리모컨일 뿐) | 프로세스 재실행 후 최신 세션으로 재접속 |
