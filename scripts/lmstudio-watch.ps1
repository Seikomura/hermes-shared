# lmstudio-watch.ps1 - Watchdog: เช็คว่า LM Studio (daemon + โมเดล + server) ยังทำงานไหม
# ถ้าอะไรหาย/ตาย -> กู้คืนทันที กันกรณี "ข้อความแรกช้าเพราะต้องโหลดโมเดลใหม่"
# รันทุก 2 นาทีผ่าน Task Scheduler: LMStudioWatch (wscript + hidden-runner.vbs = ไร้หน้าต่าง)
$ErrorActionPreference = 'SilentlyContinue'
$LMS = "$env:USERPROFILE\.lmstudio\bin\lms.exe"

# ── auto-detect HERMES_HOME (env -> C:\AI Factory -> C:\AI_FACTORY\shared\hermes_home) ──
if ($env:HERMES_HOME -and (Test-Path $env:HERMES_HOME)) { $HERMES_HOME = $env:HERMES_HOME }
elseif (Test-Path 'C:\AI Factory')                       { $HERMES_HOME = 'C:\AI Factory' }
elseif (Test-Path 'C:\AI_FACTORY\shared\hermes_home')    { $HERMES_HOME = 'C:\AI_FACTORY\shared\hermes_home' }
else                                                     { $HERMES_HOME = 'C:\AI Factory' }

$LOG = Join-Path $HERMES_HOME 'logs\lmstudio.log'

# ── เลือกโมเดลอัตโนมัติ: เครื่องทำงาน=qwen3.5-9b / เครื่องบ้าน=qwen3-1.7b ──
$Model = 'qwen/qwen3.5-9b'
$installed = (& $LMS ls 2>&1 | Out-String)
if ($installed -notmatch 'qwen3\.5-9b') { $Model = 'qwen/qwen3-1.7b' }

$MaxLogLines = 300   # กัน log โตเกิน (watchdog รันทุก 2 นาที)

function Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    $line | Out-File -FilePath $LOG -Append -Encoding utf8
    # ตัด log เก่า (เก็บ ~300 บรรทัดสุดท้าย)
    $lines = @(Get-Content $LOG -ErrorAction SilentlyContinue)
    if ($lines.Count -gt $MaxLogLines) {
        $lines | Select-Object -Last $MaxLogLines | Set-Content -Path $LOG -Encoding utf8
    }
}

# 1) daemon ต้องรัน (headless — ถ้า GUI/daemon ถูกปิด จะ start ใหม่)
$d = (& $LMS daemon status 2>&1 | Out-String)
if ($d -notmatch 'is running') {
    Log "WATCH: daemon ตาย -> start ใหม่"
    & $LMS daemon up 2>&1 | Out-Null
    Start-Sleep -Seconds 3
}

# 2) server ต้องรันก่อน (bind 0.0.0.0:1234 = เครื่องบ้านต่อผ่าน Tailscale ได้)
$srv = (& $LMS server status 2>&1 | Out-String)
if ($srv -notmatch 'running') {
    Log "WATCH: server ตาย -> start ใหม่ (0.0.0.0:1234)"
    & $LMS server start --port 1234 --bind 0.0.0.0 2>&1 | Out-Null
}

# 3) โมเดลต้องโหลดอยู่ใน memory (ถ้าหาย = ข้อความแรกจะช้า -> โหลดใหม่ทันที)
# โหลดใช้เวลา ~20-30 วิ ดังนั้นรอ 35 วิก่อนเช็คว่าสำเร็จ (ไม่งั้นจะสรุปผิดว่าโหลดไม่สำเร็จ)
$loaded = (& $LMS ps 2>&1 | Out-String)
if ($loaded -notmatch [regex]::Escape($Model)) {
    Log "WATCH: โมเดล $Model ไม่อยู่ใน memory -> โหลดใหม่ (64K context)"
    & $LMS load $Model -c 65536 2>&1 | Out-Null
    Start-Sleep -Seconds 35
    $chk = (& $LMS ps 2>&1 | Out-String)
    if ($chk -match [regex]::Escape($Model)) { Log "WATCH: โหลดสำเร็จ" } else { Log "WATCH: โหลดยังไม่สำเร็จ (รอบหน้าจะลองใหม่)" }
}
