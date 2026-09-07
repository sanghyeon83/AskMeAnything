# AskMeAnything 윈도우 - Remote Control 세션을 창 없이 띄운다.
#
# 창(터미널)에 매달리지 않으므로 어떤 터미널을 닫아도 살아 있다.
# 단, 로그오프/재부팅하면 사라진다 - 그때 이 스크립트를 다시 실행하면 된다.
#
# 실행:  powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\remote-control\start-hidden.ps1"
# 중지:  이 파일 맨 아래 주석 참고
#
# 전제조건: 터미널 CLI가 로그인돼 있어야 한다 (claude auth status -> loggedIn: true).
#          만료됐으면  claude auth login --claudeai  로 재로그인.

$ErrorActionPreference = 'Stop'

$SessionName = 'AskMeAnything 윈도우'
$WorkDir     = 'D:\workspace\AskMeAnything'
$ClaudeExe   = Join-Path $env:USERPROFILE '.local\bin\claude.exe'

# 결과를 boot.log 에 남긴다. 자동 기동은 창이 없어 화면으로 확인할 수 없으므로,
# 부팅 후 이 파일만 보면 성공/실패와 시각을 알 수 있다.
function Write-BootLog([string]$Message) {
    $log  = Join-Path $env:USERPROFILE '.claude\remote-control\boot.log'
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1} | 마지막부팅 {2:yyyy-MM-dd HH:mm:ss}' -f (Get-Date), $Message, $boot
    Add-Content -Path $log -Value $line -Encoding utf8
    # 무한히 자라지 않게 최근 50줄만 유지
    $keep = Get-Content $log -Encoding utf8 -ErrorAction SilentlyContinue | Select-Object -Last 50
    Set-Content -Path $log -Value $keep -Encoding utf8
}

# 토큰 만료 점검을 먼저 돌린다. 세션이 이미 떠 있든 아니든 매 로그온마다 확인해야 한다.
# 작업 스케줄러로 넣으려 했으나 이 계정이 관리자가 아니라 Register-ScheduledTask 가
# Access is denied 로 거부된다 (2026-09-07 실측). 그래서 로그온 경로에 얹는다.
# 여유가 있으면 파일만 읽고 끝나므로 비용이 없다. 실패해도 세션 기동은 계속한다.
$keepalive = Join-Path $env:USERPROFILE '.claude\remote-control\token-keepalive.ps1'
if (Test-Path $keepalive) {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $keepalive | Out-Null
    } catch {
        Write-Host "토큰 점검 실패(무시하고 계속): $($_.Exception.Message)"
    }
}

# 이미 떠 있으면 중복 기동하지 않는다
$existing = Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'remote-control' -and $_.CommandLine -match [regex]::Escape($SessionName) }
if ($existing) {
    $msg = "이미 실행 중 - PID $($existing.ProcessId -join ', '). 새로 띄우지 않았습니다."
    Write-Host $msg
    Write-BootLog $msg
    exit 0
}

if (-not (Test-Path $ClaudeExe)) { throw "claude.exe 없음: $ClaudeExe" }
if (-not (Test-Path $WorkDir))   { throw "작업 폴더 없음: $WorkDir" }

$inner = "cd '$WorkDir'; & '$ClaudeExe' remote-control --name '$SessionName'"
Start-Process -FilePath 'powershell.exe' `
    -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-Command', $inner `
    -WindowStyle Hidden

Start-Sleep -Seconds 12

$now = Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'remote-control' }
if ($now) {
    $msg = "기동 완료 - PID $($now.ProcessId -join ', ') (창 없음)"
} else {
    $msg = "기동 실패 - 로그인 상태를 확인하세요: claude auth status"
}
Write-Host $msg
Write-BootLog $msg

# 중지하려면:
#   Get-CimInstance Win32_Process -Filter "Name='claude.exe'" |
#     Where-Object { $_.CommandLine -match 'remote-control' } |
#     ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
