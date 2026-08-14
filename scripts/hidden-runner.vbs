' hidden-runner.vbs - runs a PowerShell script with NO console window (window style 0).
' Usage: wscript.exe hidden-runner.vbs "C:\path\script.ps1" [args...]
' Fixes the terminal window flash caused by scheduled tasks launching
' powershell.exe directly (even with -WindowStyle Hidden, the console host
' briefly flashes). Running through wscript with window style 0 means Windows
' never creates a console for the child process.
Set sh = CreateObject("Wscript.Shell")
Dim cmd, i
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & WScript.Arguments(0) & """"
For i = 1 To WScript.Arguments.Count - 1
    cmd = cmd & " """ & WScript.Arguments(i) & """"
Next
sh.Run cmd, 0, False
