# gateway-watch.ps1 - Watchdog: เช็คว่า Hermes gateway ยัง alive ไหม (ผ่าน heartbeat)
# ถ้า heartbeat เก่าเกิน -> restart gateway ทันที กัน "bot เงียบ" ซ้ำๆ
# รันทุก 2 นาทีผ่าน Task Scheduler: HermesGatewayWatch (wscript + hidden-runner.vbs = ไร้หน้าต่าง)
$ErrorActionPreference = 'SilentlyContinue'

# ── auto-detect HERMES_HOME (env -> C:\AI Factory -> C:\AI_FACTORY\shared\hermes_home) ──
if ($env:HERMES_HOME -and (Test-Path $env:HERMES_HOME)) { $HERMES_HOME = $env:HERMES_HOME }
elseif (Test-Path 'C:\AI Factory')                       { $HERMES_HOME = 'C:\AI Factory' }
elseif (Test-Path 'C:\AI_FACTORY\shared\hermes_home')    { $HERMES_HOME = 'C:\AI_FACTORY\shared\hermes_home' }
else                                                     { $HERMES_HOME = 'C:\AI Factory' }

$LOG = Join-Path $HERMES_HOME 'logs\gateway-watch.log'
$MaxHeartbeatAgeSec = 240   # heartbeat เก่าเกิน 4 นาที = gateway ตาย/ค้าง
$MaxLogLines = 300

# ── เลือก task ที่ใช้ restart: HermesGateway (เครื่องทำงาน) หรือ AI_Factory_Gateway (เครื่องบ้าน) ──
$RestartTask = 'HermesGateway'
if (-not (Get-ScheduledTask -TaskName $RestartTask -ErrorAction SilentlyContinue)) {
    if (Get-ScheduledTask -TaskName 'AI_Factory_Gateway' -ErrorAction SilentlyContinue) {
        $RestartTask = 'AI_Factory_Gateway'
    }
}

function Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    $line | Out-File -FilePath $LOG -Append -Encoding utf8
    $lines = @(Get-Content $LOG -ErrorAction SilentlyContinue)
    if ($lines.Count -gt $MaxLogLines) {
        $lines | Select-Object -Last $MaxLogLines | Set-Content -Path $LOG -Encoding utf8
    }
}

# ── 1) อ่าน heartbeat ──
$hbPath = Join-Path $HERMES_HOME 'state\gateway.heartbeat'
$alive = $false
if (Test-Path $hbPath) {
    try {
        $hb = Get-Content $hbPath -Raw | ConvertFrom-Json
        $hbTime = [datetimeoffset]::Parse($hb.updated_at)
        $ageSec = ([datetimeoffset]::UtcNow - $hbTime).TotalSeconds
        if ($ageSec -lt $MaxHeartbeatAgeSec) {
            $alive = $true   # heartbeat สด = gateway ทำงาน
        }
    } catch { }
}

if ($alive) {
    exit 0   # ปกติ ไม่ต้องทำอะไร
}

# ── 2) heartbeat เก่า -> ตรวจ process จริง ──
# บางที gateway ยังรันอยู่แต่เขียน heartbeat ไม่ได้ (ค้าง) -> ก็ต้อง restart เหมือนกัน
$gwProcs = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='hermes.exe'" |
             Where-Object { $_.CommandLine -match 'hermes' -and $_.CommandLine -match 'gateway' })
if ($gwProcs.Count -eq 0) {
    Log "WATCH: heartbeat เก่า + ไม่พบ gateway process -> restart"
} else {
    Log "WATCH: heartbeat เก่า ($ageSec วิ) แต่พบ gateway process $($gwProcs.Count) ตัว (pid: $(($gwProcs | ForEach-Object {$_.ProcessId}) -join ',')) -> restart (gateway ค้าง)"
}

# ── 3) restart gateway ──
# 3.1 จบ task เดิม (watcher) + ฆ่า process เก่า (เฉพาะ gateway เท่านั้น — ไม่แตะอย่างอื่น)
schtasks /end /TN $RestartTask 2>&1 | Out-Null
Start-Sleep -Seconds 2
$gw = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='hermes.exe'" |
        Where-Object { $_.CommandLine -match 'hermes' -and $_.CommandLine -match 'gateway' })
foreach ($p in $gw) {
    taskkill /F /PID $p.ProcessId 2>&1 | Out-Null
}
Start-Sleep -Seconds 2

# 3.2 ล้าง pid/lock ค้าง (กัน gateway ใหม่ติด lock ของตัวเก่า)
Remove-Item (Join-Path $HERMES_HOME 'gateway.pid') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $HERMES_HOME 'gateway.lock') -Force -ErrorAction SilentlyContinue

# 3.3 เริ่มใหม่ผ่าน task (รันแบบเดียวกับตอน boot — ไร้หน้าต่าง)
schtasks /run /TN $RestartTask 2>&1 | Out-Null
Log "WATCH: สั่ง restart ผ่าน task $RestartTask แล้ว — รอ heartbeat ใหม่ ~1 นาที"

# 3.4 รอ heartbeat สด (สูงสุด 90 วิ)
$recovered = $false
for ($i = 0; $i -lt 9; $i++) {
    Start-Sleep -Seconds 10
    if (Test-Path $hbPath) {
        try {
            $hb2 = Get-Content $hbPath -Raw | ConvertFrom-Json
            $age2 = ([datetimeoffset]::UtcNow - [datetimeoffset]::Parse($hb2.updated_at)).TotalSeconds
            if ($age2 -lt $MaxHeartbeatAgeSec) { $recovered = $true; break }
        } catch { }
    }
}
if ($recovered) {
    Log "WATCH: OK — heartbeat สดแล้ว (pid $($hb2.pid))"
} else {
    Log "WATCH: ยังไม่เห็น heartbeat สดภายใน 90 วิ — รอบหน้าจะลองอีกครั้ง"
}
