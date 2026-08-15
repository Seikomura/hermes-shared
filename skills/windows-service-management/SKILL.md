---
name: windows-service-management
description: "Manage Windows services and the Hermes gateway: service startup, Task Scheduler, watchdog, lifecycle state, start/stop and health checks."
category: productivity
version: 1.1.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [windows, services, scheduled-tasks, watchdog, gateway, ops]
    related_skills: [hermes-workspace-setup, systematic-debugging]
---

## When to Use

- You want a service (Hermes Agent, Hermes Gateway, Ollama, Tailscale) to start automatically after reboot/login, or need to verify/set its startup mode.
- You need to start/stop/restart the **Hermes gateway**, check why the bot is silent, inspect scheduled tasks, or diagnose watchdog / lifecycle problems on Windows.

## Part A — Windows services (generic)

1. **Identify the service name**
   - Open Services (`services.msc`) or run:
     ```powershell
     Get-Service | Where-Object {$_.DisplayName -like "*hermes*" -or $_.Name -like "*hermes*"} | Select-Object Name, DisplayName, StartType
     ```
   - Common names: Hermes Agent `hermes`, Hermes Gateway `hermes-gateway`, Ollama `ollama`, Tailscale `tailscaled`. Telegram is a user app — use the Startup folder, not a service.

2. **Check current startup type**
   ```powershell
   Get-Service -Name <service-name> | Select-Object Name, StartType
   # or
   sc qc <service-name>
   ```

3. **Set startup type**
   ```powershell
   Set-Service -Name <service-name> -StartupType Automatic   # auto
   Set-Service -Name <service-name> -StartupType Manual      # manual
   Set-Service -Name <service-name> -StartupType Disabled    # disabled
   # or via sc:  sc config <service-name> start= auto|demand|disabled
   ```

4. **Verify** (repeat step 2) and optionally `Restart-Service -Name <service-name>`.

**Pitfalls:** some Hermes components are NOT real services (they run as user processes) — use Task Scheduler / Startup folder for those. Changing startup requires an **admin** shell. Do not disable `tailscaled` if you rely on Tailscale.

## Part B — The Hermes gateway on this setup (Task Scheduler + watchdog)

The gateway does **not** run as a real service. It runs as a normal process started by **Task Scheduler at logon**, wrapped in a **watchdog**:

```
Task Scheduler:  AI_Factory_Gateway        (trigger: at logon of the user)
   └─ wscript start_gateway_hidden.vbs     (hidden, no console window)
        └─ start_gateway.bat               (the watchdog loop)
             └─ hermes gateway             (the real process; bat waits on it)
```

- The `.bat` **relaunches the gateway whenever it exits** (crash / killed), waits ~11s between attempts, and gives up after 6 consecutive "fast fails" (exit within 60s) so a broken config does not loop forever.
- A file `state\gateway.stop` (written by `stop_gateway.bat`) tells the watchdog to exit cleanly **without relaunching** and **without** sending the Telegram alert.
- Every unexpected exit is pushed to Telegram by `watchdog_notify.py` (reads `TELEGRAM_BOT_TOKEN` + chat ids from `$HERMES_HOME\.env` — never hardcode tokens).
- The repo's shared alternative (`scripts\gateway-watch.ps1` + `HermesGatewayWatch` task) restarts the gateway when the **heartbeat** is stale (every 2 min) instead of only on process exit — pick one supervision style per machine to avoid double-restart contention.

### Golden rules

1. **Restart via the task, never by just killing the process.** `taskkill` alone leaves the watchdog alive, which relaunches the gateway anyway. Clean sequence: `schtasks /end` then `schtasks /run`.
2. **Never touch `.env` / `auth.json` / `config.yaml` without a backup first.**
3. **Check `state\gateway.lifecycle.json` before assuming the gateway is dead** — the watchdog may already be restarting it. Wait 2–4 minutes before acting.
4. When in doubt, **read the logs** (`logs\gateway.log`, `logs\watchdog.log`, `logs\errors.log`, `logs\notify.log`) before restarting anything.

### Task Scheduler basics

Git Bash gotcha: `schtasks` flags like `/query` get mangled by MSYS path conversion (`/query` → `C:/Program Files/Git/query`). Always run:

```bash
export MSYS_NO_PATHCONV=1   # then schtasks works normally in Git Bash
```

```powershell
# list / inspect
schtasks /query /tn "AI_Factory_Gateway" /fo list
schtasks /query /fo csv /nh | findstr /i "AI_Factory"

# control
schtasks /end /tn "AI_Factory_Gateway"   # stop the task (kills the bat + gateway)
schtasks /run /tn "AI_Factory_Gateway"   # start it again (hidden)
schtasks /delete /tn "AI_Factory_Gateway" /f
```

Register programmatically (idempotent, used by `install-tasks.ps1`): `Register-ScheduledTask` with `New-ScheduledTaskTrigger -AtLogOn`, `New-ScheduledTaskPrincipal -LogonType Interactive`, and `ExecutionTimeLimit ([TimeSpan]::Zero)` so the long-running watchdog is never killed by the scheduler.

### Start / stop / restart procedure

```powershell
# Restart (preferred — clean and verified):
schtasks /end /tn "AI_Factory_Gateway"
schtasks /run /tn "AI_Factory_Gateway"

# Manual stop (marks gateway.stop so the watchdog exits WITHOUT relaunching):
powershell -ExecutionPolicy Bypass -File "C:\AI_FACTORY\shared\tools\stop_gateway.bat"

# Manual start (removes any stale gateway.stop first, then launches):
powershell -ExecutionPolicy Bypass -File "C:\AI_FACTORY\shared\tools\start_gateway.bat"
```

After a restart, **wait ~30–60s** then verify (all three must line up):

```powershell
# 1) lifecycle says running
Get-Content "C:\AI_FACTORY\shared\hermes_home\state\gateway.lifecycle.json" -Raw

# 2) the PID in lifecycle.json is a live process
Get-Process -Id (Get-Content "C:\AI_FACTORY\shared\hermes_home\state\gateway.lifecycle.json" -Raw | ConvertFrom-Json).pid

# 3) gateway_state.json shows the platform connected
Get-Content "C:\AI_FACTORY\shared\hermes_home\gateway_state.json" -Raw
#   → look for: "status": "running" and the Telegram connector "connected"
```

### Health checks

| Check | Command | Healthy = |
|---|---|---|
| Heartbeat age | `Get-Item state\gateway.heartbeat` — age | < 4 minutes old |
| Process alive | `Get-Process -Name hermes` | at least one process |
| Watchdog log | `Get-Content logs\watchdog.log -Tail 10` | no repeated crash loop |
| Gateway log | `Get-Content logs\gateway.log -Tail 20` | no crash traceback |
| Errors | `Get-Content logs\errors.log -Tail 10` | no repeated FATAL |
| Telegram | `gateway_state.json` | connector `connected` |

If the heartbeat is older than ~4 min but the process is alive, the gateway is **hung** (not crashed) — the watchdog only restarts on **exit**, not on hang. Restart the task manually.

## Troubleshooting table

| Symptom | Likely cause | Action |
|---|---|---|
| Bot silent, no process | watchdog gave up (6 fast fails) | read `watchdog.log` + `errors.log`, fix config, `schtasks /run` |
| Bot silent, process alive | hung, not crashed | `schtasks /end` + `/run` |
| Gateway exits right after start | config/env broken | check `logs\errors.log`, restore last-known-good config backup |
| Task missing | never registered / deleted | re-run `install-tasks.ps1` (idempotent) |
| Notify spam after crash | watchdog restart loop | fix root cause; `stop_gateway.bat` to silence while fixing |
| `schtasks` weird in bash | MSYS path conversion | `export MSYS_NO_PATHCONV=1` |

## Files you will touch

```
$HERMES_HOME\                      (e.g. C:\AI_FACTORY\shared\hermes_home)
├── config.yaml                    ← provider/fallback chain (never share)
├── .env                           ← tokens (never share)
├── auth.json                      ← OAuth creds (never share)
├── gateway_state.json             ← runtime status (telegram connected?)
├── logs\{gateway,agent,watchdog,errors,notify}.log
└── state\
    ├── gateway.lifecycle.json     ← pid + status of the gateway
    ├── gateway.pid / gateway.lock / gateway.stop
    └── gateway.heartbeat          ← last-ping timestamp
```

Scripts live in `$AI_FACTORY_ROOT\shared\tools\` (sibling of hermes_home): `start_gateway.bat`, `stop_gateway.bat`, `start_gateway_hidden.vbs`, `register_gateway_task.ps1`, `watchdog_notify.py`. The repo's shared alternative set (`gateway-watch.ps1`, `hidden-runner.vbs`, `health-check.ps1`, `fallback-watch.ps1`) deploys to `$HERMES_HOME` directly via `sync.ps1 -Scripts`.
