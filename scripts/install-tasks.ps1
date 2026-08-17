# install-tasks.ps1 — ลง Task Scheduler ชุดเดียวกับเครื่องทำงาน (watchdog + health-check + fallback)
# ============================================================
# ใช้ได้ทั้งเครื่องทำงานและเครื่องบ้าน (idempotent — ข้ามตัวที่มีอยู่แล้ว ไม่ลงซ้ำ)
# - HermesGatewayWatch    : restart gateway ถ้า heartbeat ค้าง (ทุก 2 นาที)
# - HermesGatewayLogonKick: restart gateway ทันทีที่ login (ถ้าตายค้างจากคืนก่อน)
# - HermesHealthCheck     : ตรวจสุขภาพทุก 30 นาที -> แจ้ง Telegram (เฉพาะมีปัญหา)
# - HermesFallbackWatch   : แจ้งเตือนเมื่อ fallback เปลี่ยนชั้น (ทุก 1 นาที)
# (v12: ลบ LMStudioWatch ออกแล้ว — ระบบเป็น API-only ไม่ใช้ LM Studio อีก)
#
# รันเองได้ หรือ sync.ps1 -Scripts จะเรียกให้อัตโนมัติ
#   powershell -ExecutionPolicy Bypass -File install-tasks.ps1 -HERMES_HOME 'C:\AI Factory'
#   powershell -ExecutionPolicy Bypass -File install-tasks.ps1 -Force   # ลงทับของเก่าทั้งหมด
# ============================================================

param(
    [string]$HERMES_HOME = 'C:\AI Factory',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$runner = Join-Path $HERMES_HOME 'hidden-runner.vbs'
$user   = if ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" } else { $env:USERNAME }

function New-WatchAction([string]$script, [string]$extra = '') {
    $arg = "`"$runner`" `"$(Join-Path $HERMES_HOME $script)`"$extra"
    New-ScheduledTaskAction -Execute 'wscript.exe' -Argument $arg
}

function New-WatchSettings([int]$limitMin) {
    New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes $limitMin) `
        -MultipleInstances IgnoreNew
}

function Ensure-Task([string]$name, [scriptblock]$create, [string]$desc) {
    $exists = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($exists -and -not $Force) {
        Write-Host "  SKIP: $name (มีอยู่แล้ว — ใช้ -Force ถ้าจะลงทับ)" -ForegroundColor DarkGray
        return
    }
    if ($exists) { Unregister-ScheduledTask -TaskName $name -Confirm:$false }
    & $create
    Write-Host "  OK: $name — $desc" -ForegroundColor Green
}

Write-Host "HERMES_HOME: $HERMES_HOME" -ForegroundColor Cyan
Write-Host "runner:      $runner" -ForegroundColor Cyan

# 1) HermesGatewayWatch — ทุก 2 นาที (restart ถ้า heartbeat ค้างเกิน 4 นาที)
Ensure-Task 'HermesGatewayWatch' {
    $a = New-WatchAction 'gateway-watch.ps1'
    $t = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 2)
    Register-ScheduledTask -TaskName 'HermesGatewayWatch' -Action $a -Trigger $t `
        -Settings (New-WatchSettings 5) `
        -Description 'Hermes gateway watchdog — restart ถ้า heartbeat ค้าง' -Force | Out-Null
} 'gateway watchdog ทุก 2 นาที'

# 2) HermesGatewayLogonKick — ตอน login (เฉพาะ user นี้)
Ensure-Task 'HermesGatewayLogonKick' {
    $a = New-WatchAction 'gateway-watch.ps1'
    $t = New-ScheduledTaskTrigger -AtLogOn -User $user
    Register-ScheduledTask -TaskName 'HermesGatewayLogonKick' -Action $a -Trigger $t `
        -Settings (New-WatchSettings 5) `
        -Description 'restart gateway ทันทีที่ login ถ้ายังตายค้าง' -Force | Out-Null
} 'gateway kick ตอน login'

# 3) HermesHealthCheck — ทุก 30 นาที (แจ้ง Telegram เฉพาะมีปัญหา)
Ensure-Task 'HermesHealthCheck' {
    $a = New-WatchAction 'health-check.ps1' ' -NotifyTelegram'
    $t = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 30)
    Register-ScheduledTask -TaskName 'HermesHealthCheck' -Action $a -Trigger $t `
        -Settings (New-WatchSettings 10) `
        -Description 'Hermes health check ทุก 30 นาที — แจ้ง Telegram เมื่อพบปัญหา' -Force | Out-Null
} 'health-check ทุก 30 นาที'

# 4) HermesFallbackWatch — ทุก 1 นาที (แจ้งเตือนเมื่อ fallback เปลี่ยนชั้น)
Ensure-Task 'HermesFallbackWatch' {
    $a = New-WatchAction 'fallback-watch.ps1'
    $t = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    Register-ScheduledTask -TaskName 'HermesFallbackWatch' -Action $a -Trigger $t `
        -Settings (New-WatchSettings 5) `
        -Description 'ตรวจ fallback ทุกชั้น แล้วแจ้งเตือน Telegram' -Force | Out-Null
} 'fallback-watch ทุก 1 นาที'

# 5) เช็ค task หลัก HermesGateway (gateway-watch.ps1 ใช้ restart ผ่าน task นี้)
$gw = Get-ScheduledTask -TaskName 'HermesGateway' -ErrorAction SilentlyContinue
if (-not $gw) {
    Write-Host "  ⚠️ ไม่พบ task HermesGateway — gateway-watch.ps1 ใช้ task นี้ในการ restart" -ForegroundColor Yellow
    Write-Host "     ถ้าเครื่องนี้ยังไม่ได้ลง Hermes gateway ให้รัน Hermes ตั้งค่าให้ก่อน แล้วรันสคริปต์นี้อีกครั้ง" -ForegroundColor Yellow
} else {
    Write-Host "  OK: HermesGateway (มีอยู่แล้ว — watchdog จะใช้ restart ผ่าน task นี้)" -ForegroundColor Green
}

Write-Host ""
Write-Host "เสร็จ — ตรวจ: schtasks /query /tn HermesGatewayWatch" -ForegroundColor Cyan
