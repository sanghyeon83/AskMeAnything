# Remote Control 운영 정리 (2026-08-10 전면 개정)

> 2026-07-27 문서를 폐기하고 새로 작성. 2026-08-10 재부팅 대화 유실 사고를 계기로
> 실제 테스트를 통해 확인된 사실만 담았다. 검증 환경: claude v2.1.222, Windows 11.

> 🍎 **맥북 구성 (2026-08-13)**: 이 문서는 Windows 기준이다. 맥에는 같은 목적의 구성이
> launchd 기반으로 구축 완료됐고, 이 문서의 함정 다수(재부팅 시 목록 증식, `-c` 취약성)가
> 신형 CLI(2.1.229)에서는 다르게 동작함이 실측으로 확인됐다.
> **맥 관련은 [2026-08-13_맥-환경-구축-정리.md](2026-08-13_맥-환경-구축-정리.md)를 볼 것.**


## 1. 개요

PC의 프로젝트 폴더들을 태블릿(Claude 앱)에서 원격 조종한다.

- 시작프로그램 `.vbs`가 부팅 시 프로젝트별 Remote Control 세션을 백그라운드로 상주시킨다
- 경로: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\claude-remote-control.vbs` — **UTF-16LE 인코딩 필수**
- 태블릿 접속: 창이 없어 QR은 안 뜨므로 Claude 앱 **세션 목록에서 이름으로 선택**
  - Code 탭의 컴퓨터 아이콘은 매번 새 세션을 만드니 사용하지 말 것

## 2. 핵심 운영 방식: `--resume <로컬UUID>` 고정 (2026-08-10부터)

`.vbs`의 각 줄은 이 명령을 실행한다:

```
claude --resume <로컬UUID> --remote-control '<표시이름>'
# 실패 시 자동 폴백: claude remote-control --name '<표시이름>'
```

- `--resume <UUID>`는 **로컬 대화 파일(`~/.claude/projects/<폴더식별자>/<UUID>.jsonl`)을 직접 읽는다.**
  서버 상태와 무관하므로 재부팅(연속 재부팅 포함)에도 항상 같은 대화로 복귀한다.
- 이어간 내용은 **같은 UUID 파일에 계속 누적**되므로, 대화를 새로 시작하지 않는 한 UUID는 갱신할 필요 없다.
- ⚠️ 어떤 프로젝트에서 **대화를 새로 시작했다면** `.vbs`의 해당 줄 UUID를 새 대화 UUID로 바꿔야 한다.
  **이걸 놓치는 것이 이 방식의 유일한 약점이고, 실제로 2026-08-13에 사고가 났다 (§10).**
- 🔴 **UUID를 `.jsonl`의 파일 수정시각(mtime)으로 고르지 말 것.** 두 가지 이유로 정반대를 집는다:
  ① 쓰기가 버퍼링돼 활발한 대화의 mtime이 뒤처진다 (§4) ② 부팅 시 resume이 **핀 파일을 건드려서**
  내용이 옛것인 핀 파일이 오히려 최신으로 보인다. 올바른 기준은 **대화 내용 안의 사용자 발화 타임스탬프** (§10).

### 현재 등록 세션 9개 (2026-08-10 기준 고정 UUID)

| 폴더 | 표시 이름 | 고정 UUID (앞 8자리) |
|---|---|---|
| D:\test_workspace\tokbell_ha | Tokbell HA | 7fbc0020 |
| D:\workspace\Tokbell | Tokbell | 34459464 |
| D:\workspace\tokbell_sender | Tokbell Sender | 6a16f951 |
| D:\workspace\rabbit-typing-adventure | Rabbit Typing | 24bdffc6 |
| D:\workspace\webs.madang.ai | Webs Madang | a5930b3a |
| D:\workspace\kafka_test | kafka test_로컬 | 25766a06 |
| D:\test_workspace\AskMeAnything | AskMeAnything | ece2a638 |
| D:\workspace\morning_economy | Morning Economy | 082a32c1 |
| D:\test_workspace\test | Test | ba14f707 (2026-08-10 추가) |

## 3. ❌ `-c`(--continue)를 쓰면 안 되는 이유 — 2026-08-10 사고로 확인

2026-08-07에 "8개 전부 `-c` 통일"을 했으나, **2026-08-10 첫 재부팅에서 8개 전부 대화가 끊겼다.**
로컬 기록은 하나도 안 지워졌고, 매 부팅마다 빈 새 대화가 시작된 것.

테스트로 확인된 사실:

1. **`remote-control -c`는 로컬 대화 파일을 보지 않는다.** 서버측/실행 중 세션 상태를 본다.
   오늘 13:19까지 기록된 1.26MB 로컬 대화가 있는 폴더에서도 `Error: No recent session found in
   this directory or its worktrees`로 실패했다.
2. 그래서 재부팅에 취약하다. 실측: 오늘 1차 부팅(13:18)에서는 이어받기 성공(태블릿에서 옛 대화에
   입력까지 함), 9분 뒤 2차 부팅(13:27)에서는 8개 전부 실패 — 6개는 조용히 빈 대화 생성,
   2개(kafka·Morning Economy)는 에러로 죽고 폴백. 같은 명령이 부팅 조건에 따라 다르게 동작한다.
3. **프로세스 CommandLine에 `-c`가 남아 있어도 이어받기 성공이 아니다.** (구 문서의 판별법 폐기.
   사고 당시 6개가 `-c`를 달고 살아 있으면서 전부 빈 대화였다.)
4. `remote-control --session-id`는 **클라우드 세션 ID(cse_/session_) 전용**이다. 로컬 UUID를 주면
   `Could not reach the server to look up session ...`으로 실패한다. 로컬 대화 복구에는 못 쓴다.
5. v2.1.222의 `claude remote-control`은 **다중 세션 서버**다(시작 시 빈 세션을 하나 pre-create,
   기본 `--create-session-in-dir` on). `-c`/`--session-id`는 `--spawn`·`--capacity`·
   `--create-session-in-dir`과 조합 불가.
6. 매 부팅 새 빈 세션이 쌓이는 부수 효과도 `--resume` 방식(단일 세션형)에서는 없다.

## 4. 이어받기 성공 판별법 (신뢰 가능한 순서)

```powershell
# 프로세스에 --resume <UUID>가 보이는지 (유일하게 쓸 만한 자동 점검)
Get-CimInstance Win32_Process -Filter "Name='claude.exe'" |
  Where-Object { $_.CommandLine -match 'remote-control' } |
  Select-Object ProcessId, CommandLine
```

**최종 확인은 태블릿에서 세션을 열어 이전 대화 내용이 보이는지 직접 보는 것.** 이것 말고는 확실한 방법이 없다.

### ❌ 판별에 쓰면 안 되는 것 (2026-08-10 실측으로 폐기)

| 지표 | 왜 못 쓰나 |
|---|---|
| `.jsonl`의 mtime | **갱신되지 않는다.** 3시간 넘게 활발히 대화 중인 AskMeAnything(`ece2a638`)의 mtime이 15:11:56에 멈춰 있었다 (확인 시각 18:25). 쓰기가 버퍼링된다 |
| `bridge-pointer.json`의 `pid` | **갱신되지 않는다.** 9개 프로젝트 중 기록된 pid가 살아 있는 경우가 하나도 없었다 (전부 옛 프로세스의 pid) |
| 프로세스 CommandLine의 `-c` | §3 참고. `-c`가 붙어 있어도 빈 대화일 수 있다 |

## 5. 새 프로젝트 등록 절차

**등록·확인은 창에서 명령을 직접 실행한다** (사용자 선호 방식. 래퍼 스크립트 만들지 않음).

1. 새 터미널에서 폴더로 이동 → `claude` 실행 → trust 확인 Yes → `/exit`
   - ⚠️ **절대 건너뛰지 말 것.** 이 단계 없이 `.vbs`에만 추가하면 백그라운드에서
     `Error: Workspace not trusted...`로 조용히 죽는다.
   - `~/.claude.json`의 `hasTrustDialogAccepted: true`는 데스크톱 앱 기록일 수 있고 CLI trust
     판정과 별개다. 설정 파일을 보고 판단하지 말 것.
   - PowerShell 5.1에는 `&&`가 없다: `cd <폴더>; claude`
2. 창에서 `claude remote-control --name "<이름>"` 실행 → QR로 태블릿 접속 확인(OK) 후 창 닫기
   - ⚠️ 이 단계에서 **`-c`를 붙이지 말 것.** 확인용으로도 이득이 없다 — `remote-control -c`는
     로컬 대화 파일을 보지 않으므로(§3) 이어받아지지도 않고, 폴더에 따라 `No recent session
     found`로 그냥 죽는다. 확인 목적에는 빈 세션이면 충분하다.
   - 🔴 **이 QR 단계는 새 이름을 처음 만들 때 생략할 수 없다.** 2026-08-10 Test 등록에서
     이 단계를 건너뛰고 `.vbs` 등록 + 백그라운드 기동만 했더니, 프로세스는 정상 상주하는데도
     **태블릿 세션 목록에 아예 나타나지 않았다.** 이미 등록된 이름은 백그라운드 기동만으로
     목록에 뜨지만, 처음 만드는 이름은 QR로 한 번 연결해야 한다.
3. 태블릿에서 이어갈 대화를 그 세션에서 시작 → UUID 확인(`~/.claude/projects/<폴더식별자>/` 최신 .jsonl)
4. `.vbs`에 `RunRC "폴더", "이름", "--resume <UUID>"` 줄 추가
   - ⚠️ `.vbs` 편집 후 RunRC 목록 전체를 반드시 재확인 (2026-08-07에 줄 누락 사고 있었음)
   - ⚠️ UTF-16LE 유지 (PowerShell로 쓸 때 `-Encoding Unicode`)
5. 재부팅 없이 바로 쓰려면 §6의 개별 복구 명령으로 그 줄만 즉시 기동

### 실제 등록 예시 — Test (2026-08-10)

```powershell
# 1) trust (창에서 직접)
cd D:\test_workspace\test; claude          # trust Yes → /exit

# 2) 확인 (창에서 직접, QR 뜸)
claude remote-control --name "Test"        # 확인 끝나면 창 닫기

# 3) .vbs에 추가
RunRC "D:\test_workspace\test",              "Test",            "--resume ba14f707-f705-4268-a7ee-45f182de4d4c"

# 4) 재부팅 없이 즉시 기동
Start-Process powershell -ArgumentList '-NoProfile','-Command',"Set-Location 'D:\test_workspace\test'; claude --resume ba14f707-f705-4268-a7ee-45f182de4d4c --remote-control 'Test'" -WindowStyle Hidden
```

> ⚠️ **핀으로 지정한 대화를 데스크톱 앱에서도 열어두지 말 것.** 같은 `.jsonl`을 두 프로세스가
> 동시에 쓰게 된다. Test 등록 당시 실제로 데스크톱 앱이 `ba14f707`을 열고 있었다.
> 확인: `Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | Where-Object { $_.CommandLine -match '<UUID앞자리>' }`
> — 결과가 2개(RC + 데스크톱 앱)면 데스크톱 탭을 닫는다.

## 6. 수동 전체 재시작

```powershell
# 기존 RC 프로세스 종료 (⚠️ .vbs 래퍼 PowerShell이 살아 있으면 폴백 빈 세션을 띄우니, 재시작 시엔 그것도 확인)
Get-CimInstance Win32_Process -Filter "Name='claude.exe'" |
  Where-Object { $_.CommandLine -match 'remote-control' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
# 전체 재기동
wscript.exe "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\claude-remote-control.vbs"
```

개별 복구(특정 대화를 지금 즉시 다시 띄우기):

```powershell
cd <폴더>
Start-Process powershell -ArgumentList '-NoProfile','-Command',"Set-Location '<폴더>'; claude --resume <UUID> --remote-control '<이름>'" -WindowStyle Hidden
```

## 7. 트러블슈팅

| 증상 | 원인 | 조치 |
|---|---|---|
| 태블릿에서 "생각 중"만 뜨고 답 없음 | PC 쪽 RC 프로세스 사망 (태블릿은 리모컨일 뿐) | §6 개별 복구 |
| 재부팅 후 대화가 빈 것으로 나옴 | `.vbs`가 `-c` 방식이거나 UUID가 옛 것 | `.vbs`를 `--resume <최신UUID>`로 |
| 백그라운드에서 조용히 죽음 | trust 미승인 / UUID 오타·파일 없음 | §5의 1단계, UUID 재확인 |
| 세션 이름이 목록에 두 개 | 수동 기동과 `.vbs` 폴백이 겹침 | 중복 프로세스 kill |
| `No recent session found` | `remote-control -c`의 정상 동작(로컬 파일 안 봄) | `-c` 쓰지 말 것 |

## 8. 기타 확인된 사실

- 데스크톱 앱에서 진행한 대화는 remote-control 계보와 다르다 (2026-08-06 확인).
  태블릿에서 이어갈 작업은 처음부터 remote-control 세션에서 시작할 것.
  (`--resume` 고정 방식이면 데스크톱 앱 대화도 물릴 가능성이 있으나 **미검증**)
- `claude --resume <UUID> --fork-session --remote-control` 포크 방식은 2026-08-07 폐기 유지
  (원본/사본 분기 문제). 현재의 `--resume`은 포크 없이 원본 대화 자체를 잇는 것이라 다르다.
- 터미널 세션 안에서 `/remote-control` 입력으로도 RC 전환 가능 (데스크톱 앱에서는 불가)
- 래퍼 스크립트(.ps1 등)는 만들지 않는다 (사용자 방침). 등록·복구는 위 명령을 창에서 직접 실행.

## 9. 사고 기록: 2026-08-10 재부팅 대화 유실

- 08-07 12:05 부팅 이후 3일 연속 가동 → 08-10 13:18 재부팅(#1) → 13:27 재재부팅(#2)
- #1에서는 `-c` 이어받기 성공 (kafka 옛 대화의 last-prompt에 "pc 재부팅 했어. 안녕"이 남아 있음)
- #2에서 8개 전부 끊김. 로컬 파일은 무손실. 당일 `--resume` 방식으로 전 세션 복구 완료
- 복구에서 제외된(파일은 보존됨) 대화:
  - AskMeAnything — 08-10 오후 사용자 지정으로 옛 본대화 `ece2a638`(720KB, 08-07 마감)로 핀 변경·즉시 기동함.
    다른 후보: `34898bdc`(08-07 시작~08-10까지 이어진 별개 대화), `4df1e125`(사고 조사 대화).
    바꾸려면 `.vbs`의 AskMeAnything 줄 UUID만 교체
  - Morning Economy `2cb81627` — 사고 직후(08-10 13:41) 빈 세션에서 진행한 짧은 대화(7문답).
    본대화 `082a32c1`로 핀 지정됨

## 10. 사고 기록: 2026-08-13 — 핀이 낡아 08-07 대화로 복귀

### 무슨 일이 있었나

08-13 09:43 재부팅 후 태블릿 AskMeAnything 세션을 여니 **08-10에 한 대화가 없고 08-07 대화가 떠 있었다.**
그 세션의 Claude는 08-07 시점 기억을 가진 채 깨어나, 이미 폐기된 07-27 문서를 최신인 줄 알고 다루었다.

원인은 단순하다. `.vbs`의 AskMeAnything 핀이 `ece2a638`(08-07 대화)이었고,
08-10 대화는 `4df1e125`라는 **다른 UUID**여서 애초에 불려오지 않았다.
`ece2a638`의 기록 분포를 보면 08-07이 240건, 08-13이 22건, **08-10은 0건**이다.

§9에 적힌 대로 08-10에 `ece2a638`을 직접 고른 것이라 시스템 오작동은 아니다.
**"핀을 갱신하지 않으면 조용히 옛 대화로 돌아간다"는 구조적 약점이 3일 뒤에 발현된 것**이다.
로컬 파일은 이때도 무손실이었다.

### 왜 미리 못 알아챘나

증상이 **재부팅 전에는 보이지 않는다.** 핀이 낡아도 그날 쓰던 세션은 멀쩡히 돌아가고,
다음 부팅에서야 옛 대화가 뜬다. 게다가 `.jsonl` mtime으로 점검하면 **전부 정상으로 보인다** —
부팅 시 resume이 핀 파일을 건드려 핀이 항상 최신처럼 나오기 때문이다 (실제로 9개 전부 OK로 나왔다).

### ✅ 대비책 — 핀 점검 명령 (재부팅 후 / 대화를 새로 시작한 뒤 실행)

**판별 기준은 "사용자가 실제로 말한 마지막 시각"이다.** 부팅 resume은 사용자 발화를 만들지 않으므로
이 기준만 핀 갱신 누락을 잡아낸다. 창에 그대로 붙여 넣어 실행한다 (스크립트 파일 만들지 않음, §8 방침).

```powershell
$vbs = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\claude-remote-control.vbs"
foreach ($l in (Get-Content $vbs -Encoding Unicode | Select-String '^RunRC "')) {
  if ($l -notmatch 'RunRC\s+"([^"]+)",\s*"([^"]+)",\s*"--resume ([0-9a-f-]+)"') { continue }
  $folder=$Matches[1]; $name=$Matches[2]; $pin=$Matches[3]
  $dir = "$env:USERPROFILE\.claude\projects\" + ('D--' + ($folder -replace '^D:\\','' -replace '[\\._]','-'))
  $cands = foreach ($f in (Get-ChildItem $dir -Filter *.jsonl -ErrorAction SilentlyContinue)) {
    $ts = @(Get-Content $f.FullName | ForEach-Object { try { $o=$_|ConvertFrom-Json
      if ($o.type -ne 'user') { return }
      $c = $o.message.content
      if ($c -is [string]) { if ($c -notmatch '^<(local-command|command-name|system-reminder)') { $o.timestamp } }
      else { $types=@($c|ForEach-Object{$_.type}); if (($types -contains 'text') -and ($types -notcontains 'tool_result')) { $o.timestamp } }
    } catch {} } | Where-Object {$_} | Sort-Object)
    if ($ts.Count) { [pscustomobject]@{ U=$f.BaseName; N=$ts.Count; T=[string]$ts[-1]; Pin=($f.BaseName -eq $pin) } }
  }
  $pinRow = $cands | Where-Object { $_.Pin }
  $newer  = @($cands | Where-Object { -not $_.Pin -and (-not $pinRow -or $_.T -gt $pinRow.T) } | Sort-Object T -Descending)
  $real   = @($newer | Where-Object { $_.N -ge 3 })      # 껍데기(인사 한두 마디)는 경고에서 제외
  $trivial= @($newer | Where-Object { $_.N -lt 3 })
  if ($real.Count) {
    "### $name  — *** 핀 낡음 *** (핀 $($pin.Substring(0,8)), 발화 $(if($pinRow){$pinRow.N}else{0})건, 마지막 $(if($pinRow){$pinRow.T.Substring(0,16)}else{'없음'}))"
    $real | ForEach-Object { "      더 최신: {0}  발화 {1}건  마지막 {2}" -f $_.U.Substring(0,8), $_.N, $_.T.Substring(0,16) }
  } else { "### $name  — OK" }
  $trivial | ForEach-Object { "      (참고) 껍데기 {0}  발화 {1}건  마지막 {2}" -f $_.U.Substring(0,8), $_.N, $_.T.Substring(0,16) }
}
```

**읽는 법**

- `OK` → 그 세션은 다음 부팅에도 지금 대화로 돌아온다
- `*** 핀 낡음 ***` → 핀보다 최근에 **실제로 작업한** 대화가 있다. 그 UUID로 `.vbs`를 갱신할지 판단한다
- `(참고) 껍데기` → 연결 확인용으로 한두 마디만 주고받은 대화. **경고가 아니다.** 이걸 핀으로 물리면
  본대화가 날아가니 그대로 두면 된다

> ⚠️ **필터 주의 (2026-08-13 실수):** 사용자 발화를 `content`가 문자열인 것만으로 세면 **틀린다.**
> 이미지를 붙이거나 한 메시지는 `content`가 배열(`image`+`text`)이라 0건으로 잡힌다 (실제로 Tokbell
> 본대화가 "발화 0건"으로 나왔다). 위 명령처럼 배열이면 `text` 블록 포함 & `tool_result` 미포함으로 판정해야 한다.
> `tool_result`도 `type: user`로 기록되므로 반드시 걸러야 한다.

**갱신 절차**

```powershell
# .vbs의 해당 RunRC 줄 UUID만 교체 (UTF-16LE 유지 필수)
$p = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\claude-remote-control.vbs"
$t = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::Unicode)
$t = $t.Replace('--resume <옛UUID>', '--resume <새UUID>')
[System.IO.File]::WriteAllText($p, $t, [System.Text.UnicodeEncoding]::new($false, $true))
```

그 뒤 §6의 개별 복구 명령으로 그 세션만 다시 띄우면 재부팅 없이 반영된다.

### 운영 습관 (이게 핵심)

1. **재부팅한 날은 위 점검 명령을 먼저 돌린다.** 태블릿을 열기 전에.
2. **어떤 프로젝트에서 대화를 새로 시작했으면 그 자리에서 `.vbs`를 갱신한다.** 나중으로 미루면 잊는다.
3. **태블릿에서 세션을 열면 이전 대화 내용이 보이는지 눈으로 확인한다** (§4 — 이것 말고 확실한 방법은 없다).

> 자동화(대화할 때마다 `.vbs` UUID를 자동 갱신하는 `UserPromptSubmit` 훅)를 검토했으나,
> 훅은 `.ps1` 파일을 만들어야 해서 §8의 "래퍼 스크립트 만들지 않음" 방침과 충돌한다. 보류.
