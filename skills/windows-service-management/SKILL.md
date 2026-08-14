---
name: windows-service-management
description: Set Windows service startup for Hermes, Ollama, Tailscale.
category: productivity
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: []
    related_skills: []
---

## When to Use
You want a service (e.g., Hermes Agent, Hermes Gateway, Ollama, Tailscale) to start automatically after a reboot or login, or you need to verify/set its startup mode.

## Steps
1. **Identify the service name**  
   - Open Services (`services.msc`) or run:  
     ```powershell
     Get-Service | Where-Object {$_.DisplayName -like "*hermes*" -or $_.Name -like "*hermes*"} | Select-Object Name, DisplayName, StartType
     ```  
   - Common names:  
     - Hermes Agent: `hermes` (often appears as `hermes.exe` but may be registered as a service if installed via Hermes installer).  
     - Hermes Gateway: `hermes-gateway` or similar.  
     - Ollama: `ollama` (service name often `ollama`).  
     - Tailscale: `tailscaled`.  
     - Telegram is a user app, not a service; use startup folder instead.

2. **Check current startup type**  
   ```powershell
   Get-Service -Name <service-name> | Select-Object Name, StartType
   ```
   or via `sc`:  
   ```cmd
   sc qc <service-name>
   ```

3. **Set startup type**  
   - To automatic:  
     ```powershell
     Set-Service -Name <service-name> -StartupType Automatic
     ```  
     or:  
     ```cmd
     sc config <service-name> start= auto
     ```  
   - To manual:  
     ```powershell
     Set-Service -Name <service-name> -StartupType Manual
     ```  
     or:  
     ```cmd
     sc config <service-name> start= demand
     ```  
   - To disabled:  
     ```powershell
     Set-Service -Name <service-name> -StartupType Disabled
     ```  
     or:  
     ```cmd
     sc config <service-name> start= disabled
     ```

4. **Verify the change**  
   Repeat step 2 and confirm `StartType` reflects your choice.

5. **(Optional) Restart the service immediately**  
   ```powershell
   Restart-Service -Name <service-name>
   ```  
   or:  
   ```cmd
   net stop <service-name> && net start <service-name>
   ```

## Pitfalls
- Some Hermes components may not be installed as services; they run as user processes. For those, use the Windows Startup folder (`shell:startup`) or Task Scheduler instead of service controls.
- Changing service startup requires administrative privileges. Run PowerShell or Command Prompt as Administrator.
- If a service fails to start after setting to Automatic, check the Event Viewer (`eventvwr.msc`) under Windows Logs → System for error details.
- Do not disable `tailscaled` if you rely on Tailscale for network connectivity; otherwise your VPN will not come up automatically.

## Verification
After setting, reboot or log out/in and confirm the service is running:
```powershell
Get-Service -Name <service-name> | Where-Object {$_.Status -eq 'Running'}
```
You should see the service listed with status `Running`.

## Example
Ensure Hermes Agent starts automatically:
```powershell
# Check
Get-Service -Name hermes | Select-Object Name, StartType
# Set to auto
Set-Service -Name hermes -StartupType Automatic
# Verify
Get-Service -Name hermes | Select-Object Name, StartType, Status
```
If the service is not found as a service, place a shortcut to `hermes.exe` in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup` (or `shell:startup`) to launch at login.

## References
- Microsoft docs on `Set-Service`: https://learn.microsoft.com/powershell/module/microsoft.powershell.management/set-service
- `sc.exe` reference: https://learn.microsoft.com/windows-server/administration/windows-commands/sc-config
---