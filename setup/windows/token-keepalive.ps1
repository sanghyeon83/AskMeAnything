# Claude CLI 로그인 토큰 자동 갱신 · 만료 경보 (Windows)
#
# 왜 필요한가:
#   데스크톱 앱 로그인과 터미널 CLI 로그인은 별개다. CLI 만 로그아웃되면
#   remote-control 세션이 안 뜨는데 앱은 멀쩡해서 눈치채기 어렵다.
#   이 PC 가 2026-08-26 부터 그 상태였고 9/7 에야 발견됐다.
#
# 무엇을 하나 (맥의 token-keepalive.sh 와 같은 설계):
#   1) claude auth status --json 으로 로그인 상태 확인 (API 호출 없음, 무료)
#   2) 자격증명 파일에서 만료시각만 읽는다. 토큰 값은 읽지도 기록하지도 않는다
#   3) 갱신토큰 잔여가 ThresholdDays 미만일 때만 최소 호출로 갱신을 유도한다
#   4) 로그아웃됐거나 유도 후에도 AlertDays 미만이면 알린다 (복구는 사용자만: claude auth login --claudeai)
#
# 한계: PC 가 꺼져 있는 동안은 아무것도 못 한다. 갱신 창보다 오래 꺼두면 만료된다.
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
$TaskName      = 'Claude CLI 토큰 갱신'
$ThresholdDays = 2     # 잔여가 이 아래면 갱신을 유도한다
$AlertDays     = 1     # 유도 후에도 이 아래면 알린다

# 자격증명 위치 후보. 맥은 키체인이지만 윈도우는 파일이다.
# ⚠️ 이 경로는 맥에서 확인하지 못했다. 설치 전에 실제 위치를 확인할 것.
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
            -Settings $set -Description 'Claude CLI 갱신토큰이 만료되지 않도록 점검·갱신하고, 만료가 임박하면 알린다.' `
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
if ($info.Days -gt $ThresholdDays) {
    Write-Log ('정상 — 갱신토큰 잔여 {0:N3}일 (만료 {1:yyyy-MM-dd HH:mm}). 조치 없음.' -f $info.Days, $info.Expires)
    ('{{"state":"ok","days_left":{0:N3},"checked_at":"{1:yyyy-MM-ddTHH:mm:ss}"}}' -f $info.Days, (Get-Date)) |
        Set-Content $StateFile -Encoding utf8
    exit 0
}

# ── 4) 임박 → 최소 호출로 갱신 유도 ────────────────────────
Write-Log ('임박 — 갱신토큰 잔여 {0:N3}일. 갱신 유도 호출 시작.' -f $info.Days)
try {
    Push-Location $WorkDir -ErrorAction Stop
    $null = & $ClaudeExe -p 'OK' --max-turns 1 2>$null
} catch {
    Write-Log "갱신 유도 호출 실패: $($_.Exception.Message)"
} finally {
    Pop-Location -ErrorAction SilentlyContinue
}

$after = Get-RefreshDaysLeft
if ($null -eq $after) { Write-Log '갱신 후 확인 실패'; exit 0 }
Write-Log ('갱신 유도 완료 — 잔여 {0:N3}일 → {1:N3}일' -f $info.Days, $after.Days)
('{{"state":"refreshed","days_left":{0:N3},"before":{1:N3},"checked_at":"{2:yyyy-MM-ddTHH:mm:ss}"}}' -f $after.Days, $info.Days, (Get-Date)) |
    Set-Content $StateFile -Encoding utf8

if ($after.Days -lt $AlertDays) {
    Send-Alert ('갱신토큰이 곧 만료됩니다 (잔여 {0:N1}일). 자동 갱신이 듣지 않았습니다. claude auth login --claudeai 하세요.' -f $after.Days)
}
exit 0
