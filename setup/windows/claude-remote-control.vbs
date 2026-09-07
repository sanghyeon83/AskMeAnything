Option Explicit
' Claude Remote Control autostart - AskMeAnything (Windows)
' Created 2026-09-07. Replaces the 2026-08 multi-session .vbs (archived at
' %USERPROFILE%\.claude\remote-control-archive\claude-remote-control.vbs.disabled).
'
' What it does: after a boot-settle delay, runs start-hidden.ps1 with no window.
' That script starts ONE session:  claude remote-control --name "AskMeAnything <win>"
' and skips launching if one is already running.
'
' Requires the terminal CLI to be logged in:  claude auth status  ->  loggedIn: true
' If it expired:  claude auth login --claudeai
'
' To disable: rename this file to claude-remote-control.vbs.disabled
' This file is intentionally ASCII-only, so its encoding does not matter.
' The Korean session name lives in start-hidden.ps1 (UTF-8 with BOM).

Dim sh, home, script, cmd
Set sh = CreateObject("WScript.Shell")

' Wait for network, credential store and shell to settle after logon.
WScript.Sleep 90000

home = sh.ExpandEnvironmentStrings("%USERPROFILE%")
script = home & "\.claude\remote-control\start-hidden.ps1"

cmd = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & script & """"

' 0 = hidden window, False = do not wait for it to finish
sh.Run cmd, 0, False
