# sync.ps1 — ดึงสกิลล่าสุดจาก repo hermes-shared ไปลง Hermes ของเครื่องนี้
# ============================================================
# Repo นี้คือ CENTER (source of truth):
#   แก้สกิลที่ repo\skills\  ->  รัน sync.ps1 (ลงเครื่องนี้)  ->  commit + push
#   อีกเครื่อง: git pull (หรือรัน sync.ps1 ที่ pull ให้อัตโนมัติ)
#
# ใช้ได้ทั้งเครื่องทำงานและเครื่องบ้าน (ระบุ -HERMES_HOME ถ้า config อยู่ที่อื่น)
#
# วิธีใช้:
#   powershell -ExecutionPolicy Bypass -File sync.ps1            # pull + ลงสกิล
#   powershell -ExecutionPolicy Bypass -File sync.ps1 -SkipPull  # ไม่ pull (offline / เพิ่ง push)
#   powershell -ExecutionPolicy Bypass -File sync.ps1 -Scripts   # ลงสกิล + สคริปต์ ops + ลง Task Scheduler
#   powershell -ExecutionPolicy Bypass -File sync.ps1 -Import    # (ฉุกเฉิน) เอา�สกิลที่แก้มือที่เครื่องนี้ กลับเข้า repo
# ============================================================

param(
    [string]$HERMES_HOME = 'C:\AI Factory',   # โฟลเดอร์ที่เก็บ config.yaml ของ Hermes
    [switch]$SkipPull,                         # ข้าม git pull
    [switch]$Scripts,                          # ลงสคริปต์ ops (repo\scripts) + ลง Task Scheduler ด้วย
    [switch]$Import                            # เอา�สกิล local ของเครื่องนี้ กลับเข้า repo (ทิศทางกลับ)
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$log  = Join-Path $repo 'sync.log'

function Write-Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}

# --- 0) เช็ค HERMES_HOME ---
$skillsDir = Join-Path $HERMES_HOME 'skills'
if (-not (Test-Path $HERMES_HOME)) {
    Write-Log "[ERROR] ไม่พบ HERMES_HOME: $HERMES_HOME — ระบุใหม่: -HERMES_HOME 'C:\เส้นทาง\ของคุณ'"
    exit 1
}
if (-not (Test-Path $skillsDir)) {
    New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
    Write-Log "สร้างโฟลเดอร์สกิลใหม่: $skillsDir"
}

# --- 1) pull ล่าสุดจาก GitHub ---
if (-not $SkipPull) {
    Write-Log "git pull ..."
    Push-Location $repo
    try {
        & git pull --ff-only 2>&1 | ForEach-Object { Write-Log "  pull> $_" }
    } finally {
        Pop-Location
    }
}

# --- 2) IMPORT (ฉุกเฉิน): เอา�สกิลที่แก้ที่เครื่องนี้ กลับเข้า repo ---
if ($Import) {
    Write-Log "IMPORT: คัดลอกสกิล local กลับเข้า repo (จาก $skillsDir)"
    $imports = @(
        @{ src = Join-Path $skillsDir 'windows-service-management';        dst = Join-Path $repo 'skills\windows-service-management' },
        @{ src = Join-Path $skillsDir 'productivity\hermes-workspace-setup'; dst = Join-Path $repo 'skills\productivity\hermes-workspace-setup' }
    )
    foreach ($i in $imports) {
        if (Test-Path $i.src) {
            $dstDir = Split-Path $i.dst
            if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item $i.src $i.dst -Recurse -Force
            Write-Log "  OK: $($i.src)"
        } else {
            Write-Log "  ⚠️ ไม่พบ: $($i.src)"
        }
    }
    Write-Log "IMPORT เสร็จ — อย่าลืม: cd repo; git add -A; git commit; git push"
    exit 0
}

# --- 3) DEPLOY สกิล: copy ทุกโฟลเดอร์ใน repo\skills -> HERMES_HOME\skills ---
#     (merge เท่านั้น ไม่ลบสกิล builtin / สกิลอื่นที่ไม่ได้อยู่ใน repo)
Write-Log "DEPLOY สกิล -> $skillsDir"
$n = 0
Get-ChildItem (Join-Path $repo 'skills') -Directory | ForEach-Object {
    Copy-Item $_.FullName $skillsDir -Recurse -Force
    Write-Log "  OK: $($_.Name)"
    $n++
}
if ($n -eq 0) { Write-Log "  ⚠️ repo\skills ว่างเปล่า — ยังไม่มีสกิลให้ลง" }

# --- 4) DEPLOY สคริปต์ (เฉพาะ -Scripts): repo\scripts -> HERMES_HOME + ลง Task Scheduler ---
if ($Scripts) {
    Write-Log "DEPLOY สคริปต์ -> $HERMES_HOME"
    Get-ChildItem (Join-Path $repo 'scripts') -File | ForEach-Object {
        Copy-Item $_.FullName $HERMES_HOME -Force
        Write-Log "  OK: $($_.Name)"
    }

    # ลง Task Scheduler (watchdog/health-check/fallback — ข้ามตัวที่มีอยู่แล้ว; v12: ไม่มี LMStudioWatch แล้ว)
    Write-Log "ลง Task Scheduler (install-tasks.ps1) ..."
    & (Join-Path $repo 'scripts\install-tasks.ps1') -HERMES_HOME $HERMES_HOME
}

# --- 5) สรุป ---
Write-Log "เสร็จ — ตรวจด้วย: hermes skills list"
Write-Host ""
Write-Host "✅ เสร็จ — ตรวจ: hermes skills list" -ForegroundColor Green
Write-Host "   (ควรเห็น windows-service-management + hermes-workspace-setup เป็น local / enabled)" -ForegroundColor DarkGray
