# ============================================================
#  AI FACTORY - Register Gateway auto-start at logon (Task Scheduler)
#  Run this once (as current user) to create the task:
#    powershell -ExecutionPolicy Bypass -File C:\AI_FACTORY\shared\tools\register_gateway_task.ps1
#  Unregister later with:  schtasks /Delete /TN "AI_Factory_Gateway" /F
# ============================================================

$taskName   = "AI_Factory_Gateway"
$action     = New-ScheduledTaskAction -Execute "wscript.exe" `
              -Argument '"C:\AI_FACTORY\shared\tools\start_gateway_hidden.vbs"'
$trigger    = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERNAME"
$principal  = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" `
              -LogonType Interactive -RunLevel Limited
# Restart up to 3 times (1 min apart) if it exits unexpectedly;
# ExecutionTimeLimit 0 = no kill of the long-running gateway.
$settings   = New-ScheduledTaskSettingsSet -StartWhenAvailable `
              -ExecutionTimeLimit ([TimeSpan]::Zero) `
              -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -Action $action `
  -Trigger $trigger -Principal $principal -Settings $settings `
  -Description "Start AI FACTORY Telegram Gateway at logon" -Force

Write-Host "OK: registered task '$taskName' (triggers at logon of $env:USERNAME)"
