# Claude CLI 재로그인 (Windows)
#
# 기본 동작은 "조용히" 이다. 창을 띄우지 않고 로그인을 끝낸다.
# 브라우저에 Claude 세션이 살아 있으면 사람 개입 없이 완료된다.
# 조용한 시도가 실패하면 사람이 마무리할 수 있도록 보이는 창을 띄운다.
#
# 수동 실행:
#   powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\remote-control\relogin.ps1"
#   powershell -ExecutionPolicy Bypass -File "...\relogin.ps1" -Visible     # 창을 보면서
#
# 붙여넣기 없이 끝날 때의 원리 (2026-09-08 윈도우 실측):
#   claude.exe 가 127.0.0.1 에 임시 리스너를 연다. 브라우저가 호스팅 콜백
#   페이지(platform.claude.com)를 거쳐 그 리스너로 코드를 넘긴다.
#   그래서 redirect_uri 가 localhost 가 아니어도 자동으로 끝날 수 있다.
#
#   !! 다만 이게 항상 되는 게 아니다. 같은 날 성공 4연속 뒤 실패 4연속이었고,
#      실패할 때도 리스너는 정상적으로 열려 있었다. 맥에서도 같은 모양이 나왔다.
#      (아침 3회 성공 후 그날 내내 자동 완료 안 됨)
#      브라우저 세션 생존과 localhost 도달만으로는 설명되지 않는다. 조건을 모른다.
#      그래서 보이는 창 폴백은 필수다. 지우지 말 것.
#
# 성공 판정에 대하여 (실측으로 배운 것):
#   갱신토큰 만료시각이 "밀렸는지" 로 판정하면 안 된다. 로그인이 성공해도
#   만료가 그대로이거나 오히려 뒤로 갈 수 있다.
#   (2026-09-08 실측: 성공 3회가 10-08 07:16 -> 10-07 15:20 -> 10-07 02:22)
#   반대로 로그인을 안 하면 만료는 절대 안 바뀐다 — 3시간 무변동 확인.
#   성공하면 프로세스가 스스로 종료코드 0 으로 끝난다. 실패하면
#   "Paste code here if prompted >" 에서 stdin 을 붙잡고 영원히 안 끝난다.
#   그래서 판정은 [스스로 종료 + 코드 0 + 자격증명 파일 재기록] 으로 한다.
#
# 이 파일은 UTF-8 with BOM 이어야 한다. BOM 이 없으면 PowerShell 5.1 이 cp949 로 읽어 한글이 깨진다.

param(
    [int]$TimeoutSec = 300,   # 로그인 완료를 기다리는 최대 시간(초). 실측 28~150초.
    [switch]$Visible,         # 사람이 보는 창에서 대화식으로 실행
    [switch]$NoFallback       # 실패해도 창을 띄우지 않는다 (폴백 재귀 방지)
)

$ClaudeExe = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
$CredFile  = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$Log       = Join-Path $env:USERPROFILE '.claude\remote-control\token-keepalive.log'
$Email     = 'shpark@ibank.co.kr'
$Self      = $PSCommandPath

function Write-Log([string]$Message) {
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message
    Add-Content -Path $Log -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
}

function Say([string]$Message, [string]$Color = 'Gray') {
    if ($Visible) { Write-Host $Message -ForegroundColor $Color }
}

# 갱신토큰 만료시각만 읽는다. 토큰 값은 읽지도 남기지도 않는다.
function Get-Expiry {
    try {
        $o = Get-Content $CredFile -Raw -Encoding utf8 -ErrorAction Stop | ConvertFrom-Json
        if ($o.claudeAiOauth) { $o = $o.claudeAiOauth }
        if (-not $o.refreshTokenExpiresAt) { return $null }
        return [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$o.refreshTokenExpiresAt).LocalDateTime
    } catch { return $null }
}

function Get-CredWrite {
    try { return (Get-Item $CredFile -ErrorAction Stop).LastWriteTime } catch { return [datetime]::MinValue }
}

if (-not (Test-Path $ClaudeExe)) {
    Write-Log "!! claude 실행파일 없음: $ClaudeExe"
    Say "claude 실행파일을 찾을 수 없습니다: $ClaudeExe" 'Red'
    exit 1
}

$mode      = if ($Visible) { '보이는 창' } else { '조용히' }
$startedAt = Get-Date
$credBefore = Get-CredWrite
$before     = Get-Expiry
Write-Log ('재로그인 시작 ({0}) — 이전 만료 {1}' -f $mode,
           $(if ($before) { '{0:yyyy-MM-dd HH:mm}' -f $before } else { '알 수 없음' }))

$ok   = $false
$tail = ''

if ($Visible) {
    Write-Host ''
    Write-Host '--------------------------------------------' -ForegroundColor Cyan
    Write-Host ' Claude CLI 재로그인' -ForegroundColor Cyan
    Write-Host ' 브라우저가 열리면 승인해 주세요.' -ForegroundColor Cyan
    Write-Host ' 코드가 보이면 이 창에 붙여넣으시면 됩니다.' -ForegroundColor DarkGray
    Write-Host '--------------------------------------------' -ForegroundColor Cyan
    Write-Host ''
    & $ClaudeExe auth login --claudeai --email $Email
    $ok = ($LASTEXITCODE -eq 0) -and ((Get-CredWrite) -gt $credBefore)
} else {
    # 창 없이 실행한다. 브라우저는 claude.exe 가 알아서 띄운다.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $ClaudeExe
    $psi.Arguments              = 'auth login --claudeai --email "{0}"' -f $Email
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    # 스스로 끝나기를 기다린다. 끝나지 않으면 붙여넣기 대기에 걸린 것이다.
    $exited = $p.WaitForExit($TimeoutSec * 1000)

    if (-not $exited) {
        try { $p.Kill() } catch { }
        try { [void]$p.WaitForExit(5000) } catch { }
    }

    # 진단용으로 마지막 한 줄만 남긴다 (URL 은 길어서 버린다)
    try {
        $so = $p.StandardOutput.ReadToEnd()
        $ls = @($so -split "`n" | ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and $_ -notmatch '^https?://' -and $_ -notmatch 'visit:' })
        if ($ls.Count -gt 0) { $tail = $ls[-1] }
    } catch { }

    $ok = $exited -and ($p.ExitCode -eq 0) -and ((Get-CredWrite) -gt $credBefore)
    if ($exited -and $p.ExitCode -ne 0) { $tail = ('종료코드 {0}. {1}' -f $p.ExitCode, $tail) }
    if (-not $exited) { $tail = '시간 내에 끝나지 않았다(붙여넣기 대기로 추정). ' + $tail }
}

$after = Get-Expiry
if ($ok -and $null -ne $after -and $after -lt (Get-Date)) {
    $ok = $false
    $tail = '로그인은 끝났다는데 만료시각이 과거다.'
}

$took = ((Get-Date) - $startedAt).TotalSeconds

if ($ok) {
    $days = if ($after) { ($after - (Get-Date)).TotalDays } else { [double]::NaN }
    Write-Log ('재로그인 성공 ({0}, {1:N0}초) — 잔여 {2:N3}일 (만료 {3:yyyy-MM-dd HH:mm})' -f $mode, $took, $days, $after)
    Say ''
    Say ('완료 — 다음 재로그인까지 {0:N1}일 (만료 {1:yyyy-MM-dd HH:mm})' -f $days, $after) 'Green'
    Say '   이 창은 닫으셔도 됩니다.'
    if ($Visible) { Write-Host ''; Write-Host '(3분 뒤 자동으로 닫힙니다)' -ForegroundColor DarkGray; Start-Sleep -Seconds 180 }
    exit 0
}

Write-Log ('!! 재로그인 실패 ({0}, {1:N0}초){2}' -f $mode, $took, $(if ($tail) { " — $tail" } else { '' }))

if (-not $Visible -and -not $NoFallback) {
    # 조용한 시도가 실패했다 = 브라우저 세션이 끊겼거나 localhost 홉이 막혔다.
    # 사람이 마무리할 수 있게 보이는 창으로 한 번 더 띄운다.
    Write-Log '   보이는 창으로 폴백한다 (사람이 승인/붙여넣기 해야 한다)'
    try {
        $inner = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -Visible -NoFallback' -f $Self
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', 'start', '""', $inner -WindowStyle Normal -ErrorAction Stop
    } catch {
        Write-Log "!! 폴백 창 기동 실패: $($_.Exception.Message)"
    }
} else {
    Say ''
    Say '로그인이 완료되지 않았습니다.' 'Red'
    Say '   직접 실행해 보세요:  claude auth login --claudeai'
    if ($Visible) { Write-Host ''; Start-Sleep -Seconds 180 }
}

exit 1
