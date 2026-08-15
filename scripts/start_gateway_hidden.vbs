' AI FACTORY - Start Telegram Gateway in a hidden (invisible) window
' Wraps start_gateway.bat so no console window flashes at logon
'
' 2-LAYER AUTO-RESTART:
'   Layer 1 (primary): start_gateway.bat itself is a watchdog - if the
'     gateway dies it relaunches it, so this task instance stays "Running".
'   Layer 2 (backup): bWaitOnReturn = True keeps wscript.exe alive for as
'     long as the watchdog lives, and the watchdog's exit code is propagated
'     via WScript.Quit. So if the WATCHDOG itself is killed, the task counts
'     as failed and Task Scheduler "restart on failure" relaunches it
'     (up to 3 times, 1 min apart) - for trigger-started (logon) runs.
Set shell = CreateObject("WScript.Shell")
exitCode = shell.Run("cmd /c ""C:\AI_FACTORY\shared\tools\start_gateway.bat""", 0, True)
WScript.Quit exitCode
