# setup-home-machine.ps1 — เตรียมเครื่องที่บ้านให้ตรงกับเครื่องทำงาน
# 1) เพิ่มชั้น fallback Nous Portal (solar-pro4:free)
# 2) เปลี่ยน local AI จาก Ollama (100.77.88.33:11434) → LM Studio (100.77.88.33:1234)
#    + อัปเดตชื่อโมเดล qwen3:8b → qwen/qwen3.5-9b
# 3) เช็คว่า login Nous ยังไง + restart gateway
#
# วิธีใช้: เปิด PowerShell ที่เครื่องบ้าน แล้วรัน:
#   powershell -ExecutionPolicy Bypass -File setup-home-machine.ps1
# (วางไฟล์นี้ไว้ที่เดียวกับที่เก็บ config เช่น C:\AI Factory หรือลากไปวางที่เครื่องบ้าน)

param(
    [string]$HERMES_HOME = 'C:\AI Factory',        # เปลี่ยนถ้าเครื่องบ้านเก็บ config ที่อื่น
    [string]$WorkIP       = '100.77.88.33',        # Tailscale IP ของเครื่องทำงาน (เปลี่ยนถ้าไม่ตรง)
    [switch]$SkipLogin                              # ข้ามขั้นตอน login Nous (ถ้า login ไว้แล้ว)
)

$ErrorActionPreference = 'Stop'
$cfg  = Join-Path $HERMES_HOME 'config.yaml'
$envf = Join-Path $HERMES_HOME '.env'
$auth = Join-Path $HERMES_HOME 'auth.json'
$backup = "$cfg.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

function Write-Step([string]$t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Write-Ok([string]$t)   { Write-Host "  OK: $t" -ForegroundColor Green }
function Write-Warn([string]$t) { Write-Host "  ⚠️ $t" -ForegroundColor Yellow }

# ── 0) ตรวจไฟล์พื้นฐาน ──────────────────────────────────────────
if (-not (Test-Path $cfg)) {
    Write-Host "❌ ไม่พบ config.yaml ที่ $cfg" -ForegroundColor Red
    Write-Host "   ระบุตำแหน่งใหม่ด้วย: -HERMES_HOME 'C:\เส้นทาง\ของคุณ'"
    exit 1
}
$old = Get-Content $cfg -Raw -Encoding UTF8

# ── 1) สำรอง config ─────────────────────────────────────────────
Write-Step "1) สำรอง config เดิม"
Copy-Item $cfg $backup -Force
Write-Ok "สำรองไว้ที่ $backup (ลบได้เมื่อมั่นใจว่าใช้ได้)"

# ── 2) เปลี่ยน Ollama → LM Studio (base_url + ชื่อโมเดล) ─────────
Write-Step "2) เปลี่ยน local AI: Ollama (11434) → LM Studio (1234)"
$new = $old
$changes = @()
if ($new -match '11434') {
    $new = $new -replace '100\.77\.88\.33:11434', "${WorkIP}:1234"
    $changes += "base_url: 11434 → ${WorkIP}:1234"
}
# ชื่อโมเดล (ทั้งใน fallback และ reasoning_overrides)
if ($new -match 'qwen3:8b') {
    $new = $new -replace 'qwen3:8b', 'qwen/qwen3.5-9b'
    $changes += "model: qwen3:8b → qwen/qwen3.5-9b"
}
# เผื่อเครื่องบ้านใช้ port 11434 ที่ IP อื่น (ไม่ใช่ 100.77.88.33)
if ($new -match ':11434') {
    $new = $new -replace ':11434', ':1234'
    $changes += "port: 11434 → 1234 (IP อื่น)"
}
if ($changes.Count -eq 0) {
    Write-Ok "ไม่พบ 11434/qwen3:8b — local AI อาจตั้งไว้แบบอื่นแล้ว (ดูข้างล่าง)"
} else {
    foreach ($c in $changes) { Write-Ok $c }
}

# ── 3) เพิ่มชั้น Nous Portal (ถ้ายังไม่มี) ────────────────────────
Write-Step "3) เพิ่มชั้น fallback Nous Portal (solar-pro4:free)"
if ($new -match 'solar-pro4') {
    Write-Ok "มีชั้น Nous อยู่แล้ว — ข้าม"
} elseif ($new -match 'provider: nous') {
    Write-Ok "มี provider: nous อยู่แล้ว — ข้าม"
} else {
    # แทรกก่อน entry custom (LM Studio) ถ้ามี ไม่งั้นต่อท้าย fallback_providers
    $nousEntry = "  - provider: nous`n    model: upstage/solar-pro4:free`n"
    if ($new -match '(?m)^(\s*-\s*provider:\s*custom)') {
        $new = $new -replace '(?m)^(\s*-\s*provider:\s*custom)', ($nousEntry + '$1')
        Write-Ok "แทรกชั้น Nous ก่อน LM Studio (custom)"
    } else {
        $new = $new -replace '(?m)^(fallback_providers:)', ('$1' + "`n" + $nousEntry.TrimEnd("`n"))
        Write-Ok "ต่อท้าย fallback_providers (ไม่เจอ entry custom)"
    }
}

# ── 4) เขียน config ใหม่ (ถ้ามีการเปลี่ยนแปลง) ───────────────────
if ($new -ne $old) {
    # เซฟเป็น UTF-8 (พร้อม BOM ถ้าไฟล์เดิมมี BOM — กันภาษาไทยเพี้ยน)
    $enc = if ([System.IO.File]::ReadAllBytes($cfg)[0] -eq 0xEF -and
               [System.IO.File]::ReadAllBytes($cfg)[1] -eq 0xBB) {
        New-Object System.Text.UTF8Encoding($true)
    } else { New-Object System.Text.UTF8Encoding($false) }
    [System.IO.File]::WriteAllText($cfg, $new, $enc)
    Write-Ok "เขียน config.yaml แล้ว"
} else {
    Write-Warn "config ไม่มีการเปลี่ยนแปลง"
}

# ── 5) ตรวจ/ตั้งค่า Nous login ───────────────────────────────────
Write-Step "5) Nous Portal (ชั้นฟรีของ Hermes)"
if ($SkipLogin) {
    Write-Ok "ข้าม (ใช้ -SkipLogin)"
} else {
    $HERMES = Join-Path $env:USERPROFILE 'AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe'
    if (-not (Test-Path $HERMES)) {
        Write-Warn "ไม่พบ hermes.exe ที่ $HERMES — ระบุ path เองแล้วรันใหม่ หรือข้ามด้วย -SkipLogin"
    } else {
        $env:HERMES_HOME = $HERMES_HOME
        $info = (& $HERMES portal info 2>&1 | Out-String)
        if ($info -match 'logged in') {
            Write-Ok "Nous login แล้ว — ใช้ได้เลย"
        } else {
            Write-Host "   ยังไม่ login — กำลังเปิด device-code login..." -ForegroundColor Yellow
            Write-Host "   👉 เมื่อเห็นโค้ด (เช่น ABCD-EFGH) ให้เปิด URL + พิมพ์โค้ดใน browser"
            Write-Host "   👉 ถ้า browser เปิดอัตโนมัติ ให้กด approve ตามขั้นตอน (ต้อง login บัญชี Nous เดียวกับที่สมัคร)"
            Write-Host ""
            & $HERMES portal login
            $info2 = (& $HERMES portal info 2>&1 | Out-String)
            if ($info2 -match 'logged in') { Write-Ok "Nous login สำเร็จ!" }
            else { Write-Warn "ยัง login ไม่สำเร็จ — รันคำสั่งนี้เอง: hermes portal login" }
        }
    }
}

# ── 6) restart gateway ───────────────────────────────────────────
Write-Step "6) restart gateway (ให้ config ใหม่มีผล)"
$restarted = $false
# ลองทั้งชื่อ task ที่เป็นไปได้ (เครื่องบ้านอาจตั้งชื่ออื่น)
foreach ($tn in @('HermesGateway', 'HermesGatewayHome')) {
    $chk = (schtasks /query /TN $tn 2>&1 | Out-String)
    if ($chk -notmatch 'ERROR|ไม่พบ') {
        schtasks /end /TN $tn 2>$null | Out-Null
        taskkill /F /IM hermes.exe 2>$null | Out-Null
        Start-Sleep 3
        schtasks /run /TN $tn 2>&1 | Out-Null
        Write-Ok "restart $tn แล้ว — รอ ~1 นาทีแล้วลองคุยกับ bot"
        $restarted = $true
        break
    }
}
if (-not $restarted) {
    Write-Warn "ไม่เจอ task gateway (HermesGateway) — ถ้าเครื่องบ้าน start ผ่าน Startup folder ให้ restart เครื่อง หรือรัน hermes gateway ด้วยตัวเอง"
}

# ── 7) สรุป ─────────────────────────────────────────────────────
Write-Step "✅ สรุป"
Write-Host "  ตรวจ chain ใหม่:  & hermes fallback list" -ForegroundColor White
Write-Host "  (ควรเห็น 4 ชั้น: gemini/gemma → solar-pro4:free (nous) → qwen/qwen3.5-9b @ $WorkIP:1234)" -ForegroundColor DarkGray
Write-Host "  ทดสอบ Nous:      & hermes chat -q 'ตอบว่า OK' -Q --provider nous -m upstage/solar-pro4:free --max-turns 2" -ForegroundColor White
Write-Host "  ทดสอบ LM Studio: & hermes chat -q 'ตอบว่า OK' -Q --provider custom -m qwen/qwen3.5-9b --max-turns 2" -ForegroundColor White
Write-Host ""
Write-Host "  ⚠️ หมายเหตุ: เครื่องทำงานต้องเปิดค้างไว้ + LM Studio ต้องรัน (bind 0.0.0.0:1234 ตั้งไว้แล้ว)" -ForegroundColor Yellow
Write-Host "  ถ้าเครื่องทำงานยังใช้ Ollama อยู่ (ยังไม่เปลี่ยน) ให้บอกให้เปลี่ยนก่อน แล้วค่อยรันสคริปต์นี้" -ForegroundColor Yellow
