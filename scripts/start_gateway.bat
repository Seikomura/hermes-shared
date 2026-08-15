@echo off
REM ============================================================
REM  AI FACTORY - Start Telegram Gateway (with WATCHDOG)
REM  Used by Task Scheduler (at logon) or run manually
REM  Sets required env vars, then starts: hermes gateway
REM
REM  WATCHDOG: if the gateway exits (crash / killed), wait ~11s
REM  then relaunch it. The VBS wrapper waits on this bat, so the
REM  Task Scheduler instance stays alive while the gateway runs.
REM  (Task Scheduler "restart on failure" is only a backup for
REM  when this whole watchdog is killed too.)
REM
REM  Crash-loop guard: a "fast fail" = gateway exited within 60s
REM  of starting. After 6 CONSECUTIVE fast fails the watchdog
REM  gives up (exit 1) so a broken config doesn't loop forever;
REM  a healthy long run resets the counter.
REM
REM  NOTIFY: every watchdog.log entry is also pushed to Telegram
REM  via shared\tools\watchdog_notify.py (the bot is down at that
REM  moment, so the BAT sends the alert). Log: logs\notify.log.
REM
REM  STOP: if state\gateway.stop exists (written by stop_gateway.bat)
REM  right after the gateway exits, the watchdog exits cleanly
REM  WITHOUT relaunching or sending an alert.
REM ============================================================
setlocal

set "HERMES_HOME=C:\AI_FACTORY\shared\hermes_home"
set "AI_FACTORY_ROOT=C:\AI_FACTORY"
set "HERMES_EXE=C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
set "PYTHON_EXE=C:\Users\suras\AppData\Local\Programs\Python\Python311\python.exe"
set "LIFECYCLE=C:\AI_FACTORY\shared\hermes_home\state\gateway.lifecycle.json"
set "WATCHLOG=C:\AI_FACTORY\shared\hermes_home\logs\watchdog.log"
set "NOTIFYLOG=C:\AI_FACTORY\shared\hermes_home\logs\notify.log"
set "STOPFILE=C:\AI_FACTORY\shared\hermes_home\state\gateway.stop"

REM --- Fresh start: clear any stale stop marker (an explicit start wins) ---
if exist "%STOPFILE%" del "%STOPFILE%" >nul 2>&1

REM --- Guard: skip if the gateway PID (from lifecycle.json) is still a live process ---
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "try { $l = Get-Content -Raw '%LIFECYCLE%' | ConvertFrom-Json; if ($l.pid -and (Get-Process -Id $l.pid -ErrorAction SilentlyContinue)) { 'RUNNING' } } catch { }"`) do set "GW_STATE=%%p"
if /I "%GW_STATE%"=="RUNNING" exit /b 0

cd /d C:\AI_FACTORY
REM --- Telegram IPv4 proxy (forces IPv4; fixes flaky Telegram over broken IPv6 ISP route)
set "TELEGRAM_PROXY=http://127.0.0.1:8899"
powershell -NoProfile -Command "try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 8899); $c.Close() } catch { Start-Process -WindowStyle Hidden -FilePath '%PYTHON_EXE%' -ArgumentList 'C:\AI_FACTORY\shared\tools\telegram-ipv4-proxy.py --port 8899 --log C:\AI_FACTORY\shared\hermes_home\logs\telegram-proxy.log' }" >nul 2>&1

set /a FASTFAILS=0

:watchdog
REM --- Stop requested while idle (mid ping)? exit before relaunching ---
if exist "%STOPFILE%" (
  del "%STOPFILE%" >nul 2>&1
  echo [%date% %time%] stop requested - watchdog exiting >> "%WATCHLOG%"
  exit /b 0
)
for /f "usebackq delims=" %%t in (`powershell -NoProfile -Command "[int](New-TimeSpan -Start (Get-Date '1970-01-01') -End (Get-Date)).TotalSeconds"`) do set "T0=%%t"
"%HERMES_EXE%" gateway
set "GATEWAY_EXIT=%errorlevel%"
REM --- Stop requested? exit cleanly without relaunching / notifying ---
if exist "%STOPFILE%" (
  del "%STOPFILE%" >nul 2>&1
  echo [%date% %time%] stop requested - watchdog exiting >> "%WATCHLOG%"
  exit /b 0
)
echo [%date% %time%] gateway exited (code %GATEWAY_EXIT%) - restarting >> "%WATCHLOG%"
"%PYTHON_EXE%" "C:\AI_FACTORY\shared\tools\watchdog_notify.py" >> "%NOTIFYLOG%" 2>&1
for /f "usebackq delims=" %%t in (`powershell -NoProfile -Command "[int](New-TimeSpan -Start (Get-Date '1970-01-01') -End (Get-Date)).TotalSeconds"`) do set "T1=%%t"
set /a RUNTIME=T1-T0
if "%RUNTIME%"=="" set RUNTIME=0
if %RUNTIME% GEQ 60 (set /a FASTFAILS=0) else (set /a FASTFAILS+=1)
if %FASTFAILS% GEQ 6 (
  echo [%date% %time%] giving up after %FASTFAILS% fast fails - check config >> "%WATCHLOG%"
  "%PYTHON_EXE%" "C:\AI_FACTORY\shared\tools\watchdog_notify.py" >> "%NOTIFYLOG%" 2>&1
  exit /b 1
)
REM ~11s pause before relaunch (ping 12x; bulletproof sleep, no stdin needed)
ping -n 12 127.0.0.1 >nul
goto watchdog
