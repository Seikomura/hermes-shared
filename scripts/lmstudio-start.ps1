# lmstudio-start.ps1 - เริ่ม LM Studio แบบ headless (ไร้หน้าต่าง) ตอน boot
# 1) เริ่ม daemon   2) โหลดโมเดล qwen3.5-9b   3) เริ่ม server bind 0.0.0.0:1234
# รันผ่าน hidden-runner.vbs (Task Scheduler: LMStudioServer) — ไม่มีหน้าต่างเด้ง
$ErrorActionPreference = 'SilentlyContinue'
$LMS = "$env:USERPROFILE\.lmstudio\bin\lms.exe"
$LOG = 'C:\AI Factory\logs\lmstudio.log'
$Model = 'qwen/qwen3.5-9b'

"=== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') start ===" | Out-File -FilePath $LOG -Append -Encoding utf8

# 1) daemon ต้องรันก่อน (headless — ไม่เปิดหน้าต่าง GUI)
& $LMS daemon up 2>&1 | Out-File -FilePath $LOG -Append -Encoding utf8

# รอ daemon พร้อม (สูงสุด 30 วิ)
$ready = $false
for ($i = 0; $i -lt 15; $i++) {
    $s = (& $LMS daemon status 2>&1 | Out-String)
    if ($s -match 'is running') { $ready = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ready) { "ERROR: daemon not ready" | Out-File -FilePath $LOG -Append -Encoding utf8; exit 1 }

# 2) โหลดโมเดล (ไม่โหลดซ้ำถ้าโหลดอยู่แล้ว) — ตรวจว่าสำเร็จจริง ไม่ใช่แค่รันคำสั่ง
$loaded = (& $LMS ps 2>&1 | Out-String)
if ($loaded -notmatch 'qwen/qwen3.5-9b') {
    "Loading $Model ..." | Out-File -FilePath $LOG -Append -Encoding utf8
    & $LMS load $Model -c 65536 2>&1 | Out-File -FilePath $LOG -Append -Encoding utf8   # 64K context = Hermes ต้องการขั้นต่ำ
    Start-Sleep -Seconds 2
    $chk = (& $LMS ps 2>&1 | Out-String)
    if ($chk -match 'qwen/qwen3.5-9b') {
        "OK: $Model loaded (64K context)" | Out-File -FilePath $LOG -Append -Encoding utf8
    } else {
        "WARN: load ไม่สำเร็จ — watchdog (lmstudio-watch.ps1) จะลองใหม่ใน 2 นาที" | Out-File -FilePath $LOG -Append -Encoding utf8
    }
} else {
    "already loaded" | Out-File -FilePath $LOG -Append -Encoding utf8
}

# 3) เริ่ม server (bind 0.0.0.0 = เข้าถึงได้ผ่าน Tailscale จากเครื่องที่บ้าน)
$running = (& $LMS server status 2>&1 | Out-String)
if ($running -notmatch 'running') {
    & $LMS server start --port 1234 --bind 0.0.0.0 2>&1 | Out-File -FilePath $LOG -Append -Encoding utf8
} else {
    "server already running" | Out-File -FilePath $LOG -Append -Encoding utf8
}

# ยืนยันว่า API ตอบแล้ว
Start-Sleep -Seconds 3
try {
    $r = Invoke-WebRequest -Uri 'http://localhost:1234/v1/models' -TimeoutSec 10 -UseBasicParsing
    if ($r.StatusCode -eq 200) { "OK: API responding (qwen3.5-9b)" | Out-File -FilePath $LOG -Append -Encoding utf8 }
} catch {
    "WARN: API not responding yet: $($_.Exception.Message)" | Out-File -FilePath $LOG -Append -Encoding utf8
}
