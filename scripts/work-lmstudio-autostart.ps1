# ============================================================
#  work-lmstudio-autostart.ps1
#  ให้ LM Studio เครื่องทำงาน เปิดเองพร้อม Windows + โหลดโมเดล
#  แล้วเปิด server (bind 0.0.0.0) ให้เครื่องบ้านเรียกผ่าน Tailscale ได้
#
#  วิธีใช้ (รันที่เครื่องทำงาน):
#    powershell -ExecutionPolicy Bypass -File work-lmstudio-autostart.ps1
#
#  ลง Task Scheduler ให้รันอัตโนมัติตอน login (รันครั้งเดียว):
#    schtasks /create /tn "LMStudioAutostart" /tr "powershell -ExecutionPolicy Bypass -File \"C:\เส้นทาง\work-lmstudio-autostart.ps1\"" /sc onlogon /rl highest /f
#    schtasks /run /tn "LMStudioAutostart"   # ทดสอบรันทันที
#  ลบทาสก์เมื่อไม่เอาแล้ว:
#    schtasks /delete /tn "LMStudioAutostart" /f
# ============================================================

param(
    [string]$Model        = 'qwen/qwen3.5-9b',   # โมเดลที่จะโหลด (ดูได้จาก `lms ls`)
    [int]$Port            = 1234,                # port เดียวกับที่ Hermes เครื่องบ้านเรียก
    [int]$Context         = 65536,               # context ที่โหลด (ตรงกับ custom_providers ใน config เครื่องบ้าน)
    [int]$RetryContext    = 32768,               # ลองใหม่ด้วยค่านี้ถ้า RAM/VRAM ไม่พอ
    [string]$LmsPath      = '',                  # ระบุ path lms.exe ตรง ๆ ถ้าหาไม่เจออัตโนมัติ
    [string]$LogPath      = '',                  # ไฟล์ log (default: อยู่ข้างสคริปต์)
    [switch]$CheckOnly    = $false               # แค่เช็คสภาพ (lms + โมเดล) ไม่เปิด server/ไม่โหลดโมเดล
)

$ErrorActionPreference = 'Continue'

# --- หา path ของสคริปต์ + ตั้ง log ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $LogPath) { $LogPath = Join-Path $scriptDir 'work-lmstudio-autostart.log' }

function Write-Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
    Write-Host $line
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

# --- หา lms CLI ---
function Find-Lms {
    if ($LmsPath -and (Test-Path $LmsPath)) { return $LmsPath }
    $candidates = @(
        (Join-Path $env:USERPROFILE '.lmstudio\bin\lms.exe'),          # มาตรฐานใหม่
        'C:\Users\Public\.lmstudio\bin\lms.exe',
        "$env:ProgramFiles\LM Studio\lms.exe",
        "$env:LOCALAPPDATA\Programs\LM Studio\lms.exe"
    )
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    $fromPath = (Get-Command lms.exe -ErrorAction SilentlyContinue)
    if ($fromPath) { return $fromPath.Source }
    return $null
}

$lms = Find-Lms
if (-not $lms) {
    Write-Log "[ERROR] หา lms.exe ไม่เจอ — ระบุ -LmsPath 'C:\...\lms.exe' (หรือเปิด LM Studio GUI อย่างน้อย 1 ครั้งก่อน)"
    exit 1
}
Write-Log "lms: $lms"

# --- 1) เปิด server (bind 0.0.0.0 = ให้ Tailscale เครื่องอื่นเข้าถึงได้) ---
$serverStatus = & $lms server status 2>&1 | Out-String
if ($serverStatus -match 'running') {
    Write-Log "server: กำลังรันอยู่แล้ว ($serverStatus)"
} else {
    Write-Log "server: กำลังเปิด (port $Port, bind 0.0.0.0) ..."
    & $lms server start -p $Port --bind 0.0.0.0 2>&1 | ForEach-Object { Write-Log "  server> $_" }
    Start-Sleep -Seconds 3
}

# --- 2) โหลดโมเดล (เช็คก่อนว่ามีอยู่ในเครื่อง) ---
$hasModel = (& $lms ls 2>&1 | Out-String) -match [regex]::Escape($Model)

if ($CheckOnly) {
    Write-Log "[CHECK-ONLY] lms พร้อมใช้แล้ว; โมเดล $Model อยู่บนเครื่อง: $hasModel"
    (& $lms ls 2>&1) | ForEach-Object { Write-Log "  ls> $_" }
    exit 0
}

if (-not $hasModel) {
    Write-Log "[ERROR] ยังไม่มีโมเดล $Model ในเครื่อง — เปิด LM Studio แล้วโหลด/ดาวน์โหลดก่อน (ดูได้จากคำสั่ง lms ls)"
}

function Test-Loaded([string]$key) {
    return (& $lms ps 2>&1 | Out-String) -match [regex]::Escape($key)
}

if (-not (Test-Loaded $Model)) {
    Write-Log "กำลังโหลด $Model (context $Context) ..."
    & $lms load $Model -c $Context -y 2>&1 | ForEach-Object { Write-Log "  load> $_" }
    Start-Sleep -Seconds 5
    if (-not (Test-Loaded $Model)) {
        Write-Log "โหลดที่ context $Context ไม่สำเร็จ (RAM/VRAM น่าจะไม่พอ) — ลอง $RetryContext ..."
        & $lms load $Model -c $RetryContext -y 2>&1 | ForEach-Object { Write-Log "  load(retry)> $_" }
        Start-Sleep -Seconds 5
    }
} else {
    Write-Log "$Model โหลดอยู่แล้ว"
}

# --- 3) รอจนกว่า API จะตอบโมเดลนี้ (รอสูงสุด ~180 วิ เผื่อโหลดช้า) ---
$ok = $false
for ($i = 1; $i -le 36; $i++) {
    try {
        $models = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/models" -TimeoutSec 5 -ErrorAction Stop
        if ($models.data.id -contains $Model) { $ok = $true; break }
    } catch { }
    Start-Sleep -Seconds 5
}

if ($ok) {
    Write-Log "[DONE] ✅ $Model พร้อมใช้แล้วที่ http://127.0.0.1:$Port/v1/models"
    Write-Log "       เครื่องบ้านเช็คได้: curl http://<IP-Tailscale>:${Port}/v1/models"
} else {
    Write-Log "[WARN] server/API ยังไม่ตอบ (รอครบ 180 วิ) — เปิด LM Studio GUI ดูว่ามี error อะไร แล้วรันสคริปต์ใหม่"
}
