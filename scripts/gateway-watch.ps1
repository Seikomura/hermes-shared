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
$MaxHeartbeatAgeSec = 900   # heartbeat เก่าเกิน 15 นาที = gateway ตาย/ค้าง (ทน Telegram หลุดช่วงสั้น ๆ ได้)
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

# ── 0) Telegram IPv4 proxy self-heal (port 8899) ──
# proxy อาจตายเองได้ (process หลุด) โดยที่ gateway ยังทำงาน -> heartbeat ยังสด แต่ Telegram ต่อไม่ได้
# ต้องตรวจ proxy ทุก 2 นาที (รันทุกครั้ง ไม่ใช่แค่ตอน heartbeat เก่า) — ไม่ต้อง restart gateway
$ProxyPython = 'C:\Users\suras\AppData\Local\Programs\Python\Python311\python.exe'
$ProxyScript = 'C:\AI_FACTORY\shared\tools\telegram-ipv4-proxy.py'
$ProxyLog    = Join-Path $HERMES_HOME 'logs\telegram-proxy.log'
$proxyUp = $false
try {
    $c = New-Object Net.Sockets.TcpClient
    $c.Connect('127.0.0.1', 8899)
    $c.Close()
    $proxyUp = $true
} catch { }
if (-not $proxyUp) {
    Log "PROXY: port 8899 ตาย -> เริ่ม telegram-ipv4-proxy.py ใหม่"
    if (Test-Path $ProxyPython) {
        Start-Process -WindowStyle Hidden -FilePath $ProxyPython -ArgumentList "`"$ProxyScript`" --port 8899 --log `"$ProxyLog`""
    } else {
        Log "PROXY: ไม่พบ python ที่ $ProxyPython"
    }
}

# ── 0.5) LM Studio fallback alert (ทุก 2 นาที) ──
# ถ้า turn ตกถึงชั้นสุดท้าย (provider=lmstudio = qwen3-1.7b CPU-only) -> ส่ง Telegram แจ้ง
# เตือนว่าคำตอบอาจช้า/ถูกตัด 15 นาที — state file กันส่งซ้ำ (ดู lmstudio-alert.py)
$LmsAlertScript = 'C:\AI_FACTORY\shared\tools\lmstudio-alert.py'
if (Test-Path $LmsAlertScript) {
    & $ProxyPython $LmsAlertScript 2>&1 | Out-Null
}

# ── 1) อ่าน heartbeat (retry กัน partial write) ──
# ⚠️ gateway เขียน heartbeat ไฟล์แบบ truncate+write (ไม่ atomic) — watcher อาจอ่านเจอ
#    ไฟล์ครึ่งเดียว (JSON เพี้ยน) -> parse ล้ม -> "heartbeat เก่า" ผิด ๆ -> ฆ่า gateway ที่ปกติ
#    (เจอจริง 23:05-23:09: watcher ฆ่า gateway ที่ heartbeat สด ทุก 2 นาที)
#    แก้: parse ล้ม = อ่านใหม่สูงสุด 3 ครั้ง ห่างกัน 1 วิ (รอให้เขียนเสร็จ)
$hbPath = Join-Path $HERMES_HOME 'state\gateway.heartbeat'
$alive = $false
$ageSec = $null
if (Test-Path $hbPath) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $hb = Get-Content $hbPath -Raw | ConvertFrom-Json
            $hbTime = [datetimeoffset]::Parse($hb.updated_at)
            $ageSec = ([datetimeoffset]::UtcNow - $hbTime).TotalSeconds
            if ($ageSec -lt $MaxHeartbeatAgeSec) {
                $alive = $true   # heartbeat สด = gateway ทำงาน
            }
            break   # parse สำเร็จ -> ออก loop
        } catch {
            # parse ล้ม (partial write) -> ลองอ่านใหม่; ครั้งที่ 3 ก็ยังล้ม -> ถือว่าไม่สด
            Start-Sleep -Milliseconds 1000
        }
    }
}

if ($alive) {
    exit 0   # ปกติ ไม่ต้องทำอะไร
}

# ── 2) heartbeat เก่า -> ตรวจ process จริง ──
# บางที gateway ยังรันอยู่แต่เขียน heartbeat ไม่ได้ (ค้าง) -> ก็ต้อง restart เหมือนกัน
# ⚠️ อย่า schtasks /run เอง! bat loop (start_gateway.bat) spawn gateway เองและคอย restart
#    ถ้าเรา start task ซ้อน -> 2 bat + 2 gateway เขียน heartbeat ไฟล์เดียวกัน -> JSON เพี้ยน
#    -> watcher parse ล้ม (heartbeat เก่า) -> restart ซ้ำ วนไม่จบ (เจอจริง 22:31-22:43)
#    วิธีที่ถูก: ฆ่า gateway ที่ค้างเท่านั้น -> bat loop ตัวเดียวที่รออยู่เห็น exit -> restart เอง
$gwProcs = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='hermes.exe'" |
             Where-Object { $_.CommandLine -match 'hermes' -and $_.CommandLine -match 'gateway' })
if ($gwProcs.Count -eq 0) {
    # ไม่มี gateway process -> bat loop ก็ควรจะ restart อยู่แล้ว; ถ้าไม่มี bat เลย -> ใช้ task เป็น backup
    $hasBat = @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe' OR Name='wscript.exe'" |
                Where-Object { $_.CommandLine -match 'start_gateway' }).Count -gt 0
    if ($hasBat) {
        Log "WATCH: heartbeat เก่า + ไม่พบ gateway process (แต่มี bat loop) -> รอ bat restart เอง"
        exit 0
    }
    Log "WATCH: heartbeat เก่า + ไม่พบ gateway process + ไม่มี bat loop -> ใช้ task start ใหม่"
} else {
    # ถ้า process เพิ่ง start (< $BootGraceSec วินาที) = กำลัง boot (RAM เต็ม/เครื่องช้า -> boot >3 นาทีได้)
    # restart ซ้ำตอน boot ยังไม่เสร็จ = วนไม่จบ (เจอจริง 22:31-22:37: restart ทุก 2 นาที) -> ให้เวลาอีก ข้ามรอบนี้
    $BootGraceSec = 300
    $youngest = $gwProcs | Sort-Object CreationDate | Select-Object -First 1
    $bootAgeSec = $null
    try { $bootAgeSec = [int]((Get-Date) - $youngest.CreationDate).TotalSeconds } catch { }
    if ($bootAgeSec -ne $null -and $bootAgeSec -lt $BootGraceSec) {
        Log "WATCH: heartbeat เก่า แต่ gateway เพิ่ง start ($bootAgeSec วิ < $BootGraceSec) = กำลัง boot -> ข้ามรอบนี้ (ให้เวลา)"
        exit 0
    }
    Log "WATCH: heartbeat เก่า ($ageSec วิ) + gateway process เก่า ($bootAgeSec วิ) -> ฆ่า gateway (bat loop จะ restart เอง)"
}

# ── 3) ฆ่า gateway ค้าง (เฉพาะ process — ไม่ start task ซ้อน กัน 2 bat ชนกัน) ──
foreach ($p in $gwProcs) {
    taskkill /F /PID $p.ProcessId 2>&1 | Out-Null
}
Start-Sleep -Seconds 2

# ล้าง pid/lock ค้าง (กัน gateway ใหม่ติด lock ของตัวเก่า)
Remove-Item (Join-Path $HERMES_HOME 'gateway.pid') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $HERMES_HOME 'gateway.lock') -Force -ErrorAction SilentlyContinue

# มี bat loop อยู่แล้ว -> ปล่อยให้ restart เอง (รอ heartbeat สด สูงสุด 120 วิ)
$hasBatLoop = @(Get-CimInstance Win32_Process -Filter "Name='cmd.exe' OR Name='wscript.exe'" |
                Where-Object { $_.CommandLine -match 'start_gateway' }).Count -gt 0
if ($hasBatLoop) {
    Log "WATCH: ฆ่า gateway ค้างแล้ว — bat loop จะ restart เอง (รอ heartbeat ~2 นาที)"
    $recovered = $false
    for ($i = 0; $i -lt 12; $i++) {
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
        Log "WATCH: OK — bat loop restart แล้ว heartbeat สด (pid $($hb2.pid))"
    } else {
        Log "WATCH: ยังไม่เห็น heartbeat สดภายใน 120 วิ — รอบหน้าจะลองอีกครั้ง"
    }
    exit 0
}

# ไม่มี bat loop (เช่นถูกปิด) -> ใช้ task start เป็น backup
schtasks /run /TN $RestartTask 2>&1 | Out-Null
Log "WATCH: ไม่มี bat loop -> start ผ่าน task $RestartTask แล้ว"
$recovered = $false
for ($i = 0; $i -lt 12; $i++) {
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
    Log "WATCH: ยังไม่เห็น heartbeat สดภายใน 120 วิ — รอบหน้าจะลองอีกครั้ง"
}
