# home-use-work-local.ps1 — ให้เครื่องที่บ้านใช้ local AI ของเครื่องทำงาน (ผ่าน Tailscale)
# แก้เฉพาะชั้น fallback custom → ชี้ไป LM Studio เครื่องทำงาน (100.77.88.33:1234)
# ไม่แตะ Nous / ไม่แตะ Ollama / ไม่แตะอย่างอื่น — เซฟสุดสำหรับ config ที่ต่างกัน
#
# วิธีใช้ (รันที่เครื่องบ้าน):
#   powershell -ExecutionPolicy Bypass -File home-use-work-local.ps1

param(
    [string]$HERMES_HOME = 'C:\AI Factory',   # เปลี่ยนถ้าเครื่องบ้านเก็บ config ที่อื่น
    [string]$WorkIP      = '100.77.88.33',    # Tailscale IP ของเครื่องทำงาน
    [switch]$SkipRestart                      # ไม่ restart gateway (ถ้าจะ restart เอง)
)

$ErrorActionPreference = 'Stop'
$cfg    = Join-Path $HERMES_HOME 'config.yaml'
$backup = "$cfg.bak-local-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

if (-not (Test-Path $cfg)) {
    Write-Host "❌ ไม่พบ config.yaml ที่ $cfg" -ForegroundColor Red
    Write-Host "   ระบุใหม่: -HERMES_HOME 'C:\เส้นทาง\ของคุณ'"
    exit 1
}

Write-Host "`n=== 1) สำรอง config ===" -ForegroundColor Cyan
Copy-Item $cfg $backup -Force
Write-Host "  OK: $backup" -ForegroundColor Green

Write-Host "`n=== 2) ชี้ local fallback ไปเครื่องทำงาน ($WorkIP:1234) ===" -ForegroundColor Cyan
$old = Get-Content $cfg -Raw -Encoding UTF8
$new = $old
$changes = @()

# 1) เครื่องบ้านเคยชี้ Ollama เครื่องทำงาน (100.77.88.33:11434) → เปลี่ยนเป็น LM Studio (1234)
if ($new -match '100\.77\.88\.33:11434') {
    $new = $new -replace '100\.77\.88\.33:11434', "${WorkIP}:1234"
    $changes += "base_url: 11434 -> ${WorkIP}:1234"
}
# 2) ชื่อโมเดลเก่า → ใหม่
if ($new -match 'qwen3:8b') {
    $new = $new -replace 'qwen3:8b', 'qwen/qwen3.5-9b'
    $changes += "model: qwen3:8b -> qwen/qwen3.5-9b"
}
# 3) เผื่อเครื่องบ้านชี้เครื่องทำงานด้วย IP อื่น (ไม่ใช่ 100.77.88.33) — แก้เฉพาะบรรทัด base_url
#    ที่เป็น IP ระยะไกลเท่านั้น (ยกเว้น localhost/127.0.0.1 = Ollama ในเครื่องบ้านเอง ไม่แตะ)
$remote11434 = '(?m)^(\s*base_url:\s*https?://(?!localhost|127\.0\.0\.1)[^\r\n]*):11434'
if ($new -match $remote11434) {
    $new = $new -replace $remote11434, ('$1' + ':1234')
    $changes += "port: 11434 -> 1234 (เฉพาะ base_url ของ IP ระยะไกล)"
}
# 4) เครื่องบ้านมี LM Studio ตัวเอง (base_url ชี้ localhost/127.0.0.1) → ชี้ไปเครื่องทำงานแทน
#    (เสปคต่ำ อยากใช้ local AI ของเครื่องทำงาน — เปลี่ยนทั้ง base_url + ชื่อโมเดลของ entry นี้)
$localEntry = '(?ms)(^[ \t]*-[ \t]*provider:[ \t]*custom[ \t]*\r?\n(?:(?![ \t]*-[ \t]*provider:)[ \t]+[^\r\n]*\r?\n)*)'
$repointed = $false
$new = [regex]::Replace($new, $localEntry, {
    param($m)
    $block = $m.Groups[1].Value
    if ($block -match 'https?://(localhost|127\.0\.0\.1)(:\d+)?/v1') {
        $script:repointed = $true
        $block = $block -replace 'https?://(localhost|127\.0\.0\.1)(:\d+)?/v1', "http://${WorkIP}:1234/v1"
        $block = $block -replace '(?m)^(\s*model:\s*).*$', ('$1qwen/qwen3.5-9b')
    }
    return $block
})
if ($repointed) {
    $changes += "LM Studio เครื่องบ้าน (localhost) -> ชี้เครื่องทำงาน ${WorkIP}:1234 + โมเดล qwen/qwen3.5-9b"
}

# 5) ถ้ายังไม่มี entry custom เลย → ต่อท้าย list fallback_providers (ให้เป็น fallback สุดท้าย)
if ($new -notmatch '(?m)^\s*-\s*provider:\s*custom') {
    $entry = "  - provider: custom`n    model: qwen/qwen3.5-9b`n    base_url: http://${WorkIP}:1234/v1`n"
    $block = '(?ms)^(fallback_providers:.*?)(?=^\S|\z)'
    if ($new -match $block) {
        $new = $new -replace $block, ('$1' + $entry)
        $changes += "เพิ่ม entry custom ต่อท้าย list -> ${WorkIP}:1234 (fallback สุดท้าย)"
    } else {
        Write-Host "  ⚠️ ไม่พบ fallback_providers ใน config — เปิดไฟล์ดูเองแล้วเพิ่ม entry นี้:" -ForegroundColor Yellow
        Write-Host "  - provider: custom" -ForegroundColor Yellow
        Write-Host "    model: qwen/qwen3.5-9b" -ForegroundColor Yellow
        Write-Host "    base_url: http://${WorkIP}:1234/v1" -ForegroundColor Yellow
    }
}

if ($changes.Count -eq 0) {
    Write-Host "  ⚠️ ไม่พบอะไรต้องแก้ — ตรวจ config เองว่ามี entry custom -> ${WorkIP}:1234 แล้ว" -ForegroundColor Yellow
} else {
    foreach ($c in $changes) { Write-Host "  OK: $c" -ForegroundColor Green }
}

# เขียน config (รักษา BOM เดิม — กันภาษาไทยเพี้ยน)
if ($new -ne $old) {
    $bytes = [System.IO.File]::ReadAllBytes($cfg)
    $enc = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        New-Object System.Text.UTF8Encoding($true)
    } else { New-Object System.Text.UTF8Encoding($false) }
    [System.IO.File]::WriteAllText($cfg, $new, $enc)
    Write-Host "  OK: เขียน config.yaml แล้ว" -ForegroundColor Green
} else {
    Write-Host "  config ไม่มีการเปลี่ยนแปลง" -ForegroundColor Yellow
}

# restart gateway (ไม่บังคับ)
if (-not $SkipRestart) {
    Write-Host "`n=== 3) restart gateway ===" -ForegroundColor Cyan
    $restarted = $false
    foreach ($tn in @('HermesGateway', 'HermesGatewayHome')) {
        $chk = (schtasks /query /TN $tn 2>&1 | Out-String)
        if ($chk -notmatch 'ERROR') {
            schtasks /end /TN $tn 2>$null | Out-Null
            taskkill /F /IM hermes.exe 2>$null | Out-Null
            Start-Sleep 3
            schtasks /run /TN $tn 2>&1 | Out-Null
            Write-Host "  OK: restart $tn แล้ว — รอ ~1 นาทีแล้วลองคุยกับ bot" -ForegroundColor Green
            $restarted = $true
            break
        }
    }
    if (-not $restarted) {
        Write-Host "  ⚠️ ไม่เจอ task gateway — restart เครื่อง หรือรัน hermes gateway เอง" -ForegroundColor Yellow
    }
}

Write-Host "`n=== ✅ สรุป ===" -ForegroundColor Cyan
Write-Host "  ทดสอบเชื่อมต่อ:  curl http://${WorkIP}:1234/v1/models" -ForegroundColor White
Write-Host "  (เห็น qwen/qwen3.5-9b = เชื่อมต่อได้ พร้อมใช้เป็น fallback)" -ForegroundColor DarkGray
Write-Host "  ตรวจ chain:       hermes fallback list" -ForegroundColor White
