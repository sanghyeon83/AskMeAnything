# Claude CLI 로그인 만료 감시 · 경보 (Windows)
#
# ⚠️ 이름은 keepalive 지만 "갱신"은 하지 않는다. 할 수 없기 때문이다.
#    2026-09-07 맥에서 실측: 액세스 토큰 만료 직후 강제로 갱신을 일으켜 보니
#      액세스 토큰  09-07 19:00:16 -> 09-08 02:57:08   갱신됨
#      갱신 토큰    09-11 04:25:10 -> 09-11 04:25:10   그대로
#    갱신토큰은 로그인 시점부터 약 29일 고정이고, 써도 뒤로 밀리지 않는다.
#      맥    키체인 cdat 2026-08-13 -> 만료 2026-09-11 (29일)
#      이 PC 재로그인   2026-09-07 -> 만료 2026-10-06 (29일)
#    네가 보고한 28.465일이 이 사실을 드러낸 단서였다. 맥의 3.4일과 같은 규칙으로
#    설명되지 않아 다시 쟀고, "창이 밀린다"는 전제가 깨졌다.
#    즉 한 달에 한 번은 사람이 다시 로그인해야 한다. 자동화로는 못 막는다.
#
# 왜 필요한가:
#   데스크톱 앱 로그인과 터미널 CLI 로그인은 별개다. CLI 만 로그아웃되면
#   remote-control 세션이 안 뜨는데 앱은 멀쩡해서 눈치채기 어렵다.
#   이 PC 가 2026-08-26 부터 그 상태였고 9/7 에야 발견됐다.
#
# 하는 일은 하나다 — 만료 전에 알려주는 것 (맥의 token-keepalive.sh 와 같은 설계):
#   1) claude auth status --json 으로 로그인 상태 확인 (API 호출 없음, 무료)
#   2) 자격증명 파일에서 만료시각만 읽는다. 토큰 값은 읽지도 기록하지도 않는다
#   3) WarnDays 이하로 남으면 알린다 (하루 한 번). UrgentDays 이하면 실행할 때마다 알린다
#   4) 이미 로그아웃 상태면 즉시 알린다. 복구는 사용자만 가능: claude auth login --claudeai
#
# 설치:   powershell -ExecutionPolicy Bypass -File token-keepalive.ps1 -Install
# 제거:   powershell -ExecutionPolicy Bypass -File token-keepalive.ps1 -Uninstall
# 수동:   powershell -ExecutionPolicy Bypass -File token-keepalive.ps1
#
# 이 파일은 UTF-8 with BOM 이어야 한다. BOM 이 없으면 PowerShell 5.1 이 cp949 로 읽어 한글이 깨진다.

param(
    [switch]$Install,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Continue'

$ClaudeExe     = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
$WorkDir       = 'D:\workspace\AskMeAnything'          # trust 승인된 폴더여야 한다
$RcDir         = Join-Path $env:USERPROFILE '.claude\remote-control'
$Log           = Join-Path $RcDir 'token-keepalive.log'
$BootLog       = Join-Path $RcDir 'boot.log'           # 부팅 확인용 로그에도 경고를 남긴다
$StateFile     = Join-Path $RcDir 'token.json'
$TaskName      = 'Claude CLI 로그인 만료 감시'
$WarnDays       = 5     # 이 아래로 남으면 알린다 (하루 한 번)
$UrgentDays     = 2     # 이 아래면 실행할 때마다 알린다
$AlertGapHours  = 12    # 경보 최소 간격
$AutoDays       = 7     # 이 아래면 재로그인을 자동으로 시도한다 (창 없이 조용히)
$LaunchGapHours = 12    # 자동 시도 최소 간격 (연달아 우르르 도는 것 방지)
$Relogin        = Join-Path $RcDir 'relogin.ps1'

# 자격증명 위치 후보. 맥은 키체인이지만 윈도우는 파일이다.
# 후보 1(~\.claude\.credentials.json)이 실제 위치임을 2026-09-08 확인했다.
$CredCandidates = @(
    (Join-Path $env:USERPROFILE '.claude\.credentials.json'),
    (Join-Path $env:APPDATA    'Claude\.credentials.json')
)

if (-not (Test-Path $RcDir)) { New-Item -ItemType Directory -Path $RcDir -Force | Out-Null }

function Write-Log([string]$Message) {
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message
    Add-Content -Path $Log -Value $line -Encoding utf8
    $keep = Get-Content $Log -Encoding utf8 -ErrorAction SilentlyContinue | Select-Object -Last 200
    Set-Content -Path $Log -Value $keep -Encoding utf8
}

function Start-Relogin {
    # 재로그인을 창 없이 조용히 시작한다.
    # relogin.ps1 이 알아서 다음을 한다:
    #   - 창 없이 로그인 시도 (브라우저 세션이 살아 있으면 사람 개입 없이 끝난다.
    #     2026-09-08 실측 28~150초, 종료코드 0)
    #   - 실패하면 스스로 보이는 창을 띄워 사람이 마무리하게 한다
    # 여기서는 기다리지 않는다. 감시 작업이 몇 분씩 붙잡혀 있으면 안 된다.
    if (-not (Test-Path $Relogin)) {
        Write-Log "!! 재로그인 스크립트 없음: $Relogin"
        return $false
    }
    # 이미 로그인 절차가 돌고 있으면 또 시작하지 않는다
    $running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
               Where-Object { $_.CommandLine -match 'relogin\.ps1' }
    if ($running) {
        Write-Log "   재로그인이 이미 돌고 있다 (PID $($running.ProcessId -join ',')). 새로 시작하지 않음."
        return $false
    }
    try {
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $Relogin `
            -WindowStyle Hidden -ErrorAction Stop
        Write-Log '   재로그인을 조용히 시작했다 (실패하면 relogin.ps1 이 창을 띄운다)'
        return $true
    } catch {
        Write-Log "!! 재로그인 기동 실패: $($_.Exception.Message)"
        return $false
    }
}

function Send-Alert([string]$Message) {
    Write-Log "!! 경고: $Message"
    # 부팅 확인 로그에도 남긴다 — 여기는 사람이 실제로 들여다보는 곳이다
    Add-Content -Path $BootLog -Value ('[{0:yyyy-MM-dd HH:mm:ss}] !! 로그인 경고 | {1}' -f (Get-Date), $Message) -Encoding utf8
    # 풍선 알림은 되면 좋고 안 되면 마는 보조 수단이다 (숨김 작업에서는 안 뜰 수 있다)
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
        $ni = New-Object System.Windows.Forms.NotifyIcon
        $ni.Icon = [System.Drawing.SystemIcons]::Warning
        $ni.BalloonTipTitle = 'Claude CLI 로그인'
        $ni.BalloonTipText  = $Message
        $ni.Visible = $true
        $ni.ShowBalloonTip(20000)
        Start-Sleep -Seconds 12
        $ni.Dispose()
    } catch { Write-Log "   (풍선 알림 실패: $($_.Exception.Message))" }
}

# ── 설치 / 제거 ────────────────────────────────────────────
if ($Install) {
    $me = $MyInvocation.MyCommand.Path
    # 예전 이름으로 등록된 작업이 남아 있으면 지운다. $TaskName 이 바뀐 적이 있어
    # ('Claude CLI 토큰 갱신' -> 현재 이름) 그냥 두면 -Uninstall 로도 안 지워지는
    # 고아 작업이 된다. 이름을 또 바꾸면 여기 추가할 것.
    foreach ($old in @('Claude CLI 토큰 갱신')) {
        if ($old -ne $TaskName -and (Get-ScheduledTask -TaskName $old -ErrorAction SilentlyContinue)) {
            Unregister-ScheduledTask -TaskName $old -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "옛 작업 제거: $old"
            Write-Log  "옛 이름 작업 제거됨 ($old)"
        }
    }
    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
                 -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $me)
    # 로그온 직후 1회 + 6시간마다. 오래 꺼뒀다 켠 경우가 가장 위험하므로 로그온 트리거가 핵심이다.
    $t1 = New-ScheduledTaskTrigger -AtLogOn
    $t1.Delay = 'PT3M'
    # ⚠️ -RepetitionDuration ([TimeSpan]::MaxValue) 를 쓰면 안 된다.
    #    P99999999DT23H59M59S 로 직렬화돼 작업 스케줄러가 "out of range" 로 거부한다
    #    (2026-09-07 윈도우 실측). 생략하면 무기한 반복이 된다.
    $t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) `
            -RepetitionInterval (New-TimeSpan -Hours 6)
    $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
             -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    # 실패를 삼키지 않는다. 예전 판은 등록이 거부돼도 "등록 완료" 를 찍고 0 으로 끝나서
    # 설치된 줄 알게 됐다 — 조용한 실패가 실패 자체보다 나쁘다.
    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $t1,$t2 `
            -Settings $set -Description 'Claude CLI 로그인 만료를 감시하고 임박하면 알린다. 갱신은 하지 않는다(불가능). 만료 시 사용자가 claude auth login --claudeai 로 재로그인해야 한다.' `
            -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "등록 실패: $($_.Exception.Message)"
        Write-Log  "!! 작업 등록 실패 ($TaskName): $($_.Exception.Message)"
        exit 1
    }
    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        Write-Host "등록 실패: 등록 후 작업을 찾을 수 없다"
        Write-Log  "!! 작업 등록 실패 ($TaskName): 등록 후 조회 안 됨"
        exit 1
    }
    Write-Host "등록 완료: $TaskName"
    Write-Log  "작업 등록됨 ($TaskName)"
    exit 0
}
if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "제거 완료: $TaskName"
    exit 0
}

# ── 1) 로그인 상태 (무료) ──────────────────────────────────
if (-not (Test-Path $ClaudeExe)) { Write-Log "claude.exe 없음: $ClaudeExe"; exit 1 }

$loggedIn = $null
try {
    $raw = & $ClaudeExe auth status --json 2>$null | Out-String
    $loggedIn = ($raw | ConvertFrom-Json).loggedIn
} catch { Write-Log "auth status 실패: $($_.Exception.Message)" }

if ($loggedIn -eq $false) {
    Send-Alert 'CLI 가 로그아웃됐습니다. claude auth login --claudeai 로 재로그인하세요. (remote-control 세션이 안 뜹니다)'
    '{"state":"logged_out"}' | Set-Content $StateFile -Encoding utf8
    exit 1
}

# ── 2) 갱신토큰 잔여 (만료시각만) ──────────────────────────
function Get-RefreshDaysLeft {
    foreach ($p in $CredCandidates) {
        if (-not (Test-Path $p)) { continue }
        try {
            $o = Get-Content $p -Raw -Encoding utf8 | ConvertFrom-Json
            if ($o.claudeAiOauth) { $o = $o.claudeAiOauth }
            if (-not $o.refreshTokenExpiresAt) { continue }
            $exp = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$o.refreshTokenExpiresAt).LocalDateTime
            return [PSCustomObject]@{ Days = ($exp - (Get-Date)).TotalDays; Expires = $exp; Path = $p }
        } catch { }
    }
    return $null
}

$info = Get-RefreshDaysLeft
if ($null -eq $info) {
    Write-Log '-- 자격증명에서 만료시각을 읽지 못했다 (로그인 상태는 정상). 판단 보류. $CredCandidates 경로를 확인할 것.'
    '{"state":"unknown_expiry"}' | Set-Content $StateFile -Encoding utf8
    exit 0
}

# ── 3) 여유가 있으면 아무것도 하지 않는다 ──────────────────
function Get-StateTime([string]$Field) {
    # -ErrorAction SilentlyContinue 가 없으면 상태 파일이 아직 없을 때 (첫 실행)
    # try/catch 가 값은 잡아주지만 비종료 오류가 그대로 화면·stderr 로 새어 나온다.
    try {
        return [datetime](Get-Content $StateFile -Raw -Encoding utf8 -ErrorAction SilentlyContinue | ConvertFrom-Json).$Field
    } catch { return [datetime]::MinValue }
}
$prevAlert  = Get-StateTime 'last_alert'
$prevLaunch = Get-StateTime 'last_launch'

function Save-State([string]$State, [double]$Days, [datetime]$Alert, [datetime]$Launch) {
    ('{{"state":"{0}","days_left":{1:N3},"last_alert":"{2:yyyy-MM-ddTHH:mm:ss}","last_launch":"{3:yyyy-MM-ddTHH:mm:ss}","checked_at":"{4:yyyy-MM-ddTHH:mm:ss}"}}' `
        -f $State, $Days, $Alert, $Launch, (Get-Date)) | Set-Content $StateFile -Encoding utf8
}

# 조기 종료 문턱은 "무언가 해야 하는 가장 이른 시점" 이어야 한다.
# $AutoDays 를 $WarnDays 보다 크게 잡아 놓고 $WarnDays 로 끊으면
# 그 사이 구간에서 자동 재로그인이 영영 안 돈다 — 2026-09-08 에 실제로 그랬다.
$ActDays = [Math]::Max($WarnDays, $AutoDays)

if ($info.Days -gt $ActDays) {
    Write-Log ('정상 — 재로그인까지 {0:N3}일 (만료 {1:yyyy-MM-dd HH:mm}). 조치 없음.' -f $info.Days, $info.Expires)
    Save-State 'ok' $info.Days $prevAlert $prevLaunch
    exit 0
}

# ── 4) 임박 → 자동 재로그인 + 경보 ─────────────────────────
# 갱신토큰 자체는 연장이 안 되지만, 재로그인하면 창이 29일 새로 시작된다.
# 잘 되면 창도 사람도 없이 28~150초에 끝난다. 다만 항상 되는 건 아니다
# (2026-09-08 실측: 성공 4연속 뒤 실패 4연속. 맥도 같은 모양. 원인 미상).
# 안 끝나면 relogin.ps1 이 스스로 보이는 창을 띄워 사람에게 넘긴다.
$warn     = $info.Days -lt $WarnDays
$urgent   = $info.Days -lt $UrgentDays
$overdue  = ((Get-Date) - $prevAlert).TotalHours -gt $AlertGapHours
$alertAt  = $prevAlert
$launchAt = $prevLaunch

if ($info.Days -lt $AutoDays -and ((Get-Date) - $prevLaunch).TotalHours -gt $LaunchGapHours) {
    Write-Log ('임박({0:N3}일) — 재로그인을 조용히 시작한다.' -f $info.Days)
    if (Start-Relogin) { $launchAt = Get-Date }
}

if ($urgent -or ($warn -and $overdue)) {
    Send-Alert ('CLI 로그인이 {0:N1}일 뒤 만료됩니다 (만료 {1:yyyy-MM-dd HH:mm}). 자동 재로그인을 시작했습니다. 이 경고가 계속 뜨면 claude auth login --claudeai 를 직접 실행하세요.' -f $info.Days, $info.Expires)
    $alertAt = Get-Date
} elseif ($warn) {
    Write-Log ('임박({0:N3}일)하지만 최근 경보 후 {1}시간이 안 지나 알림은 생략.' -f $info.Days, $AlertGapHours)
}
Save-State 'expiring' $info.Days $alertAt $launchAt
exit 0
