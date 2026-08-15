@echo off
REM ============================================================
REM  AI FACTORY - Stop the Telegram Gateway (watchdog) cleanly
REM
REM  NOTE: `schtasks /End` alone is NOT enough - the bat watchdog
REM  (launched via VBS/cmd) survives /End and keeps relaunching
REM  the gateway. This script:
REM    1. writes a stop marker that the watchdog checks right
REM       after the gateway exits (no relaunch, no alert)
REM    2. kills the gateway process (pid from lifecycle.json)
REM    3. ends the scheduled task (wscript/cmd)
REM  The watchdog then exits cleanly (code 0), so Task Scheduler
REM  does NOT treat it as a failure and does NOT restart it.
REM ============================================================
setlocal
set "STOPFILE=C:\AI_FACTORY\shared\hermes_home\state\gateway.stop"
set "LIFECYCLE=C:\AI_FACTORY\shared\hermes_home\state\gateway.lifecycle.json"

echo stop > "%STOPFILE%"

for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "try { (Get-Content -Raw '%LIFECYCLE%' | ConvertFrom-Json).pid } catch { 0 }"`) do set "GPID=%%p"
if not "%GPID%"=="" if not "%GPID%"=="0" taskkill /F /PID %GPID% >nul 2>&1

schtasks /End /TN "AI_Factory_Gateway" >nul 2>&1

echo Gateway stop requested. Verify no gateway process remains:
tasklist 2>nul | findstr /I hermes || echo   (no hermes process - gateway stopped)
