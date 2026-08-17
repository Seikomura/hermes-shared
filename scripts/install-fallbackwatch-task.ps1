# ติดตั้ง Task Scheduler: HermesFallbackWatch — ตรวจ fallback (ทุกชั้น API: openrouter → nous → gemini) ทุก 1 นาที
# รันผ่าน wscript.exe + hidden-runner.vbs (window style 0) เพื่อไม่ให้หน้าต่าง console กระพริบ
$ErrorActionPreference = 'Stop'

$taskName = 'HermesFallbackWatch'
$runner   = 'C:\AI Factory\hidden-runner.vbs'
$script   = 'C:\AI Factory\fallback-watch.ps1'
$action   = New-ScheduledTaskAction -Execute 'wscript.exe' `
    -Argument "`"$runner`" `"$script`""
$trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) `
    -RepetitionDuration (New-TimeSpan -Days 3650)   # 10 ปี (max ที่ Task Scheduler รับ) — repeat ต่อเนื่อง
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew

# ลบ task เก่าถ้ามี (กันซ้ำ)
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Description 'ตรวจ fallback ทุกชั้น (openrouter → nous → gemini) แล้วแจ้งเตือน Telegram' | Out-Null

Write-Output "Registered: $taskName (every 1 min)"
