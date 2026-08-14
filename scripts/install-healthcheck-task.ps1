# install-healthcheck-task.ps1
# สร้าง Task Scheduler: HermesHealthCheck — รัน health-check.ps1 ทุก 30 นาที
# และส่งผลไป Telegram เฉพาะเมื่อมีปัญหา (CRIT/WARN)
$ErrorActionPreference = 'Stop'

# รันผ่าน wscript.exe + hidden-runner.vbs (window style 0) เพื่อไม่ให้หน้าต่าง console กระพริบ
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument '"C:\AI Factory\hidden-runner.vbs" "C:\AI Factory\health-check.ps1" -NotifyTelegram'

# เริ่มครั้งแรกในอีก 1 นาที แล้ววนซ้ำทุก 30 นาที ตลอดไป
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 30)

$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName 'HermesHealthCheck' -Action $action -Trigger $trigger -Settings $settings `
    -Description 'Hermes health check ทุก 30 นาที — แจ้งเตือน Telegram เมื่อพบปัญหา' -Force

Write-Output 'HermesHealthCheck task created.'
