<#
화면 제어 (Windows) — screen-control 스킬의 실행부

캡처 · 창 조회/전면화 · 마우스 · 키보드를 한 파일에서 처리한다.

  screen.ps1 -Action info
  screen.ps1 -Action capture [-Region "x,y,w,h"] [-Scale 0.5] [-Out 경로]
  screen.ps1 -Action windows [-Filter chrome]
  screen.ps1 -Action front   -Title "부분일치"
  screen.ps1 -Action click   -X 100 -Y 200 [-Button left|right|middle] [-Double]
  screen.ps1 -Action move    -X 100 -Y 200
  screen.ps1 -Action scroll  -X 100 -Y 200 -Amount -3
  screen.ps1 -Action type    -Text "아무 글자나"
  screen.ps1 -Action key     -Text "^s"
  screen.ps1 -Action cursor

좌표계: 이 스크립트는 시작하자마자 DPI 인식을 켠다. 따라서 모든 좌표가
**물리 픽셀**이다 (이 PC 기준 1920x1200). PowerShell 기본값인 DPI 미인식
상태에서 재면 1536x960 논리 좌표가 나와 서로 어긋난다 — 섞어 쓰지 말 것.

이 파일은 UTF-8 with BOM 이어야 한다. BOM 이 없으면 PowerShell 5.1 이 cp949 로 읽어 한글이 깨진다.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('info','capture','windows','front','click','move','scroll','type','key','cursor')]
    [string]$Action,

    [string]$Region,                  # capture: "x,y,w,h"
    [string]$Out,                     # capture: 저장 경로
    [double]$Scale = 1.0,             # capture: 0.1~1.0 축소 (토큰 절약)
    [string]$Filter,                  # windows: 제목/프로세스 부분일치
    [string]$Title,                   # front: 제목 부분일치
    [IntPtr]$Handle = [IntPtr]::Zero, # front: 창 핸들
    [int]$X = [int]::MinValue,
    [int]$Y = [int]::MinValue,
    [ValidateSet('left','right','middle')]
    [string]$Button = 'left',
    [switch]$Double,
    [int]$Amount = 3,                 # scroll: 양수=위, 음수=아래
    [string]$Text,
    [int]$DelayMs = 40
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$src = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class Scr {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, int d, IntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, IntPtr e);
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] i, int cb);

  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);

  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }

  [StructLayout(LayoutKind.Sequential)]
  public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)]
  public struct HARDWAREINPUT { public uint uMsg; public ushort wParamL, wParamH; }
  [StructLayout(LayoutKind.Explicit)]
  public struct InputUnion {
    [FieldOffset(0)] public MOUSEINPUT mi;
    [FieldOffset(0)] public KEYBDINPUT ki;
    [FieldOffset(0)] public HARDWAREINPUT hi;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT { public uint type; public InputUnion u; }

  public static List<IntPtr> AllWindows() {
    var list = new List<IntPtr>();
    EnumWindows((h, l) => { list.Add(h); return true; }, IntPtr.Zero);
    return list;
  }

  // 유니코드 문자열을 그대로 입력한다 (SendKeys 와 달리 한글이 안전하다)
  public static void TypeUnicode(string s) {
    var inputs = new List<INPUT>();
    foreach (char c in s) {
      for (int k = 0; k < 2; k++) {
        var i = new INPUT();
        i.type = 1;
        i.u.ki.wVk = 0;
        i.u.ki.wScan = c;
        i.u.ki.dwFlags = (uint)(0x0004 | (k == 1 ? 0x0002 : 0));
        i.u.ki.time = 0;
        i.u.ki.dwExtraInfo = IntPtr.Zero;
        inputs.Add(i);
      }
    }
    if (inputs.Count > 0) SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf(typeof(INPUT)));
  }
}
"@
if (-not ('Scr' -as [type])) { Add-Type -TypeDefinition $src }

# 좌표를 물리 픽셀로 통일한다. 화면을 재기 전에 호출해야 한다.
[void][Scr]::SetProcessDPIAware()

function Get-ScreenBounds { [System.Windows.Forms.SystemInformation]::VirtualScreen }

function Get-WindowList {
    $out = @()
    foreach ($h in [Scr]::AllWindows()) {
        if (-not [Scr]::IsWindowVisible($h)) { continue }
        $sb = New-Object System.Text.StringBuilder 512
        [void][Scr]::GetWindowText($h, $sb, 512)
        $t = $sb.ToString()
        if (-not $t) { continue }
        $procId = 0
        [void][Scr]::GetWindowThreadProcessId($h, [ref]$procId)
        $r = New-Object Scr+RECT
        [void][Scr]::GetWindowRect($h, [ref]$r)
        $out += [pscustomobject]@{
            Handle = $h
            OwnerPid = $procId
            Name   = (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName
            Title  = $t
            X = $r.L; Y = $r.T; W = ($r.R - $r.L); H = ($r.B - $r.T)
            Min    = [Scr]::IsIconic($h)
        }
    }
    $out
}

# SetForegroundWindow 는 호출자가 포그라운드가 아니면 조용히 실패한다.
# ALT 를 한 번 눌러 포그라운드 락을 푼 뒤 다시 시도한다.
function Set-Front([IntPtr]$h) {
    [void][Scr]::ShowWindow($h, 9)
    [void][Scr]::BringWindowToTop($h)
    if ([Scr]::SetForegroundWindow($h)) { return $true }
    [Scr]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)
    [Scr]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [void][Scr]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 120
    return ([Scr]::GetForegroundWindow() -eq $h)
}

switch ($Action) {

    'info' {
        $b = Get-ScreenBounds
        $p = New-Object Scr+POINT
        [void][Scr]::GetCursorPos([ref]$p)
        $v = Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution } | Select-Object -First 1
        Write-Host ("가상화면(물리) : {0} x {1}  (원점 {2},{3})" -f $b.Width, $b.Height, $b.X, $b.Y)
        if ($v) { Write-Host ("어댑터 보고    : {0} x {1}" -f $v.CurrentHorizontalResolution, $v.CurrentVerticalResolution) }
        Write-Host ("커서           : {0}, {1}" -f $p.X, $p.Y)
        Write-Host ("창 개수        : {0}" -f (Get-WindowList).Count)
    }

    'capture' {
        $b = Get-ScreenBounds
        $rx = $b.X; $ry = $b.Y; $rw = $b.Width; $rh = $b.Height
        if ($Region) {
            $parts = $Region -split '\s*,\s*'
            if ($parts.Count -ne 4) { throw "-Region 은 'x,y,w,h' 형식이어야 한다 (받은 값: $Region)" }
            $rx = [int]$parts[0]; $ry = [int]$parts[1]; $rw = [int]$parts[2]; $rh = [int]$parts[3]
        }
        if ($rw -le 0 -or $rh -le 0) { throw "캡처 크기가 0 이하다 ($rw x $rh)" }
        if (-not $Out) {
            $Out = Join-Path (Join-Path $env:TEMP 'claude-screen') ('shot-{0:yyyyMMdd-HHmmss}.png' -f (Get-Date))
        }
        # -Out 을 직접 준 경우에도 폴더가 없으면 GDI+ 가 "generic error" 로 죽는다.
        $parent = Split-Path -Parent $Out
        if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $bmp = New-Object System.Drawing.Bitmap $rw, $rh
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($rx, $ry, 0, 0, (New-Object System.Drawing.Size($rw, $rh)))
        $g.Dispose()
        if ($Scale -gt 0 -and $Scale -lt 1.0) {
            $sw = [int]($rw * $Scale); $sh = [int]($rh * $Scale)
            $small = New-Object System.Drawing.Bitmap($bmp, (New-Object System.Drawing.Size($sw, $sh)))
            $bmp.Dispose(); $bmp = $small
        }
        $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
        $wOut = $bmp.Width; $hOut = $bmp.Height
        $bmp.Dispose()
        Write-Host ("캡처 {0}x{1} -> {2} ({3:N0} bytes)" -f $wOut, $hOut, $Out, (Get-Item $Out).Length)
        Write-Host ("원본영역 x={0} y={1} w={2} h={3}  배율={4}" -f $rx, $ry, $rw, $rh, $Scale)
    }

    'windows' {
        $list = Get-WindowList
        if ($Filter) { $list = $list | Where-Object { $_.Title -match [regex]::Escape($Filter) -or $_.Name -match [regex]::Escape($Filter) } }
        if (-not $list) { Write-Host '해당하는 창이 없다'; break }
        foreach ($w in $list) {
            Write-Host ("  hwnd={0,-10} PID={1,-6} {2,-14} 최소화={3,-5} ({4},{5}) {6}x{7}  '{8}'" -f
                        $w.Handle, $w.OwnerPid, $w.Name, $w.Min, $w.X, $w.Y, $w.W, $w.H, $w.Title)
        }
    }

    'front' {
        $h = $Handle
        if ($h -eq [IntPtr]::Zero) {
            if (-not $Title) { throw '-Title 또는 -Handle 중 하나는 필요하다' }
            $m = @(Get-WindowList | Where-Object { $_.Title -match [regex]::Escape($Title) })
            if ($m.Count -eq 0) { Write-Host "제목에 '$Title' 를 포함한 창이 없다"; exit 1 }
            if ($m.Count -gt 1) {
                Write-Host '여러 개가 맞는다 — 첫 번째를 쓴다. 정확히 지정하려면 -Handle 을 써라:'
                $m | ForEach-Object { Write-Host ("    hwnd={0} '{1}'" -f $_.Handle, $_.Title) }
            }
            $h = $m[0].Handle
        }
        $ok = Set-Front $h
        $sb = New-Object System.Text.StringBuilder 512
        [void][Scr]::GetWindowText($h, $sb, 512)
        Write-Host ("전면화 {0} : hwnd={1} '{2}'" -f $(if ($ok) { '성공' } else { '실패(다른 창이 포그라운드를 잠갔을 수 있다)' }), $h, $sb.ToString())
        if (-not $ok) { exit 1 }
    }

    { $_ -in 'click','move','scroll' } {
        if ($X -eq [int]::MinValue -or $Y -eq [int]::MinValue) { throw '-X 와 -Y 가 필요하다' }
        $b = Get-ScreenBounds
        if ($X -lt $b.X -or $Y -lt $b.Y -or $X -ge ($b.X + $b.Width) -or $Y -ge ($b.Y + $b.Height)) {
            throw ("좌표가 화면 밖이다: ({0},{1}) — 화면은 {2}x{3}" -f $X, $Y, $b.Width, $b.Height)
        }
        [void][Scr]::SetCursorPos($X, $Y)
        Start-Sleep -Milliseconds $DelayMs

        if ($Action -eq 'move') { Write-Host ("커서 이동 -> {0}, {1}" -f $X, $Y); break }

        if ($Action -eq 'scroll') {
            [Scr]::mouse_event(0x0800, 0, 0, ($Amount * 120), [IntPtr]::Zero)
            Write-Host ("스크롤 {0}틱 @ {1},{2}" -f $Amount, $X, $Y)
            break
        }

        $down = 0x0002; $up = 0x0004
        if ($Button -eq 'right')  { $down = 0x0008; $up = 0x0010 }
        if ($Button -eq 'middle') { $down = 0x0020; $up = 0x0040 }
        $times = 1
        if ($Double) { $times = 2 }
        for ($i = 0; $i -lt $times; $i++) {
            [Scr]::mouse_event($down, 0, 0, 0, [IntPtr]::Zero)
            Start-Sleep -Milliseconds 25
            [Scr]::mouse_event($up, 0, 0, 0, [IntPtr]::Zero)
            if ($i -lt $times - 1) { Start-Sleep -Milliseconds 60 }
        }
        $lbl = ''
        if ($Double) { $lbl = '더블 ' }
        Write-Host ("{0}클릭({1}) @ {2}, {3}" -f $lbl, $Button, $X, $Y)
    }

    'type' {
        if (-not $Text) { throw '-Text 가 필요하다' }
        [Scr]::TypeUnicode($Text)
        Write-Host ("입력 {0}자" -f $Text.Length)
    }

    'key' {
        if (-not $Text) { throw '-Text 가 필요하다 (SendKeys 문법: ^s, %{F4}, {ENTER} 등)' }
        [System.Windows.Forms.SendKeys]::SendWait($Text)
        Write-Host ("키 전송: {0}" -f $Text)
    }

    'cursor' {
        $p = New-Object Scr+POINT
        [void][Scr]::GetCursorPos([ref]$p)
        Write-Host ("커서 : {0}, {1}" -f $p.X, $p.Y)
    }
}
