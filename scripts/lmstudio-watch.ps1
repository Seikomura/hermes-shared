# lmstudio-watch.ps1 - Watchdog: จัดการ LM Studio แบบ "โหลดเฉพาะเมื่อจำเป็น"
# (ไม่รันทิ้งทั้งวัน — เครื่อง RAM 7.9GB เต็มง่าย ถ้าโมเดล 1.28GB ค้างใน memory ทั้งวัน)
#
# หลักการ:
#   1) bot เงียบ (ไม่มี conversation turn ใน 30 นาที) -> UNLOAD โมเดล (คืน RAM ~1.3GB)
#   2) มี turn ใหม่ -> LOAD โมเดลกลับ (fallback ชั้นสุดท้าย ⑭ พร้อมใช้)
#   3) daemon/server ที่ 1234 ต้องรันเสมอ (เบาๆ) — เป็นตัวรับคำสั่งของ LM Studio
#
# รันทุก 2 นาทีผ่าน Task Scheduler: LMStudioWatch (wscript + hidden-runner.vbs)
$ErrorActionPreference = 'SilentlyContinue'
$LMS = "$env:USERPROFILE\.lmstudio\bin\lms.exe"

# ── auto-detect HERMES_HOME ──
if ($env:HERMES_HOME -and (Test-Path $env:HERMES_HOME)) { $HERMES_HOME = $env:HERMES_HOME }
elseif (Test-Path 'C:\AI Factory')                       { $HERMES_HOME = 'C:\AI Factory' }
elseif (Test-Path 'C:\AI_FACTORY\shared\hermes_home')    { $HERMES_HOME = 'C:\AI_FACTORY\shared\hermes_home' }
else                                                     { $HERMES_HOME = 'C:\AI Factory' }

$LOG = Join-Path $HERMES_HOME 'logs\lmstudio.log'

# ── เลือกโมเดลอัตโนมัติ: เครื่องทำงาน=qwen3.5-9b / เครื่องบ้าน=qwen3-1.7b ──
$Model = 'qwen/qwen3.5-9b'
$installed = (& $LMS ls 2>&1 | Out-String)
if ($installed -notmatch 'qwen3\.5-9b') { $Model = 'qwen/qwen3-1.7b' }

# ── ค่า idle: bot เงียบนานเท่าไรถึง unload (นาที) ──
$IdleUnloadMin = 30

$MaxLogLines = 300

function Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    $line | Out-File -FilePath $LOG -Append -Encoding utf8
    $lines = @(Get-Content $LOG -ErrorAction SilentlyContinue)
    if ($lines.Count -gt $MaxLogLines) {
        $lines | Select-Object -Last $MaxLogLines | Set-Content -Path $LOG -Encoding utf8
    }
}

# ── ตรวจว่า bot เพิ่งคุยกัน turn ล่าสุดเมื่อไหร่ (จาก agent.log) ──
# ใช้ timestamp บรรทัด "conversation turn" ล่าสุด -> ถ้าเก่ากว่า IdleUnloadMin = เงียบ
function Get-LastTurnAgeMin {
    $log = Join-Path $HERMES_HOME 'logs\agent.log'
    if (-not (Test-Path $log)) { return -1 }   # ยังไม่มี log = ไม่รู้ -> ถือว่าไม่เงียบ (โหลดไว้ก่อน)
    $age = -1
    # อ่านจากท้ายไฟล์ (log โต) — หาบรรทัด turn ล่าสุด
    $lines = Get-Content $log -Tail 5000
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $ln = $lines[$i]
        if ($ln -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}).*conversation turn') {
            try {
                $ts = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss',
                    [System.Globalization.CultureInfo]::InvariantCulture)
                $age = [int]((Get-Date) - $ts).TotalMinutes
            } catch { }
            break
        }
    }
    return $age
}

# ── 1) server 1234 ต้องรัน (เบาๆ ตัวรับคำสั่ง) — เช็คผ่าน port จริง
# (หมายเหตุ: lms.exe เขียน status ไป stderr + PowerShell มองเป็น NativeCommandError
#  -> $ErrorActionPreference=SilentlyContinue จะกลืน output -> match ไม่ติด -> วน start ซ้ำ
#  วิธีที่ robust: เช็ค TCP port 1234 ตรงๆ แทนการ parse ข้อความ)
function Test-Port([int]$Port) {
    try {
        $c = New-Object Net.Sockets.TcpClient
        $c.Connect('127.0.0.1', $Port)
        $c.Close()
        return $true
    } catch { return $false }
}

# daemon + server ของ LM Studio เปิด port 1234 (ตัวรับคำสั่ง; โมเดล unload ได้อิสระ)
if (-not (Test-Port 1234)) {
    # daemon อาจตาย -> start ทั้ง daemon + server ใหม่
    $d = (& $LMS daemon status 2>&1 | Out-String)
    if ($d -notmatch 'is running') {
        Log "WATCH: daemon ตาย -> start ใหม่"
        & $LMS daemon up 2>&1 | Out-Null
        Start-Sleep -Seconds 3
    }
    Log "WATCH: server 1234 ไม่ฟัง -> start ใหม่ (0.0.0.0:1234)"
    & $LMS server start --port 1234 --bind 0.0.0.0 2>&1 | Out-Null
    Start-Sleep -Seconds 2
}

# ── 3) ตัดสินใจ load/unload ตาม activity ──
$loaded = (& $LMS ps 2>&1 | Out-String)
$modelInMem = ($loaded -match [regex]::Escape($Model))
$lastTurnAge = Get-LastTurnAgeMin

if ($modelInMem -and $lastTurnAge -ge $IdleUnloadMin) {
    # bot เงียบเกิน threshold -> unload โมเดล (คืน RAM ~1.3GB)
    Log "WATCH: bot เงียบ $lastTurnAge นาที -> unload $Model (คืน RAM)"
    & $LMS unload $Model 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    $chk = (& $LMS ps 2>&1 | Out-String)
    if ($chk -match [regex]::Escape($Model)) { Log "WATCH: unload ยังไม่สำเร็จ (รอบหน้าลองใหม่)" }
    else { Log "WATCH: unload สำเร็จ — โมเดลออกจาก memory แล้ว" }
}
elseif (-not $modelInMem -and ($lastTurnAge -lt $IdleUnloadMin -or $lastTurnAge -lt 0)) {
    # มี turn ใหม่ (หรือไม่รู้) + โมเดลไม่อยู่ -> โหลดกลับ (fallback พร้อมใช้)
    Log "WATCH: มี turn ใหม่ (เงียบ $lastTurnAge นาที) -> โหลด $Model (64K context)"
    & $LMS load $Model -c 65536 2>&1 | Out-Null
    Start-Sleep -Seconds 35
    $chk = (& $LMS ps 2>&1 | Out-String)
    if ($chk -match [regex]::Escape($Model)) { Log "WATCH: โหลดสำเร็จ" }
    else { Log "WATCH: โหลดยังไม่สำเร็จ (รอบหน้าจะลองใหม่)" }
}
# อื่นๆ (เงียบ+unload แล้ว / มี turn+loaded แล้ว) -> ไม่ต้องทำอะไร
