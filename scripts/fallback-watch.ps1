<#
.SYNOPSIS
  👀 Fallback Watch — แจ้งเตือน Telegram เมื่อ bot fallback (ทุกชั้น) แบบมี cooldown

.DESCRIPTION
  ตรวจ logs\agent.log หาเหตุการณ์ "Fallback activated: X → Y" ทุกชั้น
  (openrouter → nous → gemini — API เท่านั้น) แล้วส่งแจ้งเตือนไป Telegram

  แจ้งแบบ cooldown (กันสแปม): แจ้งครั้งเดียว แล้วเงียบภายในระยะเวลา
  ที่กำหนด (ค่าเริ่มต้น 60 นาที) — ถ้า Gemini quota หมดทั้งวัน จะได้
  แจ้งเตือนไม่เกิน 1 ครั้ง/ชั่วโมง (หรือตาม -CooldownMinutes)

  ใช้ byte-offset (state\fallback-watch.offset) + dedupe บรรทัด
  (state\fallback-watch.last) + เวลา cooldown (state\fallback-watch.cooldown)

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File fallback-watch.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File fallback-watch.ps1 -CooldownMinutes 30

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File fallback-watch.ps1 -TestSend   # ส่งข้อความทดสอบเสมอ

.NOTES
  read-only ต่อระบบ (เขียนแค่ state file ของตัวเอง) — ไม่แตะ gateway
  exit code: 0 = ไม่ส่ง / 1 = ส่งแจ้งเตือน
#>

param(
    [string]$TelegramTarget = 'telegram:1709297704',   # ปลายทาง (bot:chat_id)
    [int]$CooldownMinutes   = 60,                      # เงียบกี่นาทีหลังแจ้งครั้งล่าสุด (กันสแปม)
    [switch]$TestSend                                   # ส่งข้อความทดสอบ (ไม่ตรวจ log, ข้าม cooldown)
)

$ErrorActionPreference = 'Continue'

# ── ค่าคงที่ของระบบ (auto-detect — env -> C:\AI Factory -> C:\AI_FACTORY\shared\hermes_home) ──
if ($env:HERMES_HOME -and (Test-Path $env:HERMES_HOME)) { $HERMES_HOME = $env:HERMES_HOME }
elseif (Test-Path 'C:\AI Factory')                       { $HERMES_HOME = 'C:\AI Factory' }
elseif (Test-Path 'C:\AI_FACTORY\shared\hermes_home')    { $HERMES_HOME = 'C:\AI_FACTORY\shared\hermes_home' }
else                                                     { $HERMES_HOME = 'C:\AI Factory' }

$LOG_FILE    = Join-Path $HERMES_HOME 'logs\agent.log'
$STATE_FILE  = Join-Path $HERMES_HOME 'state\fallback-watch.offset'
$LAST_FILE   = Join-Path $HERMES_HOME 'state\fallback-watch.last'
$COOLDOWN_FILE = Join-Path $HERMES_HOME 'state\fallback-watch.cooldown'
$STATE_DIR   = Split-Path $STATE_FILE
$OVERLAP     = 4096   # อ่านย้อนหลังเล็กน้อย กันเหตุการณ์คาบเส้นอ่าน (partial line) พลาด
$MAX_LAST    = 30     # เก็บบรรทัดที่แจ้งแล้วสูงสุดกี่บรรทัด (กันไฟล์โต)

# pattern: ทุกเหตุการณ์ fallback activation ("Fallback activated: X → Y")
$FALLBACK_PATTERN = 'Fallback activated:.*→'

# ── 1) อ่านส่วนใหม่ของ agent.log (byte-offset) ───────────────────
$newText = ''
$isFirstRun = $false
if (-not $TestSend) {
    if (-not (Test-Path $LOG_FILE)) {
        Write-Host 'ℹ️ ไม่พบ logs\agent.log (gateway ยังไม่เคยรัน?) — ไม่มีอะไรให้ตรวจ'
        exit 0
    }

    # สร้าง state dir ถ้ายังไม่มี
    if (-not (Test-Path $STATE_DIR)) { New-Item -ItemType Directory -Path $STATE_DIR -Force | Out-Null }

    $fileLen = (Get-Item $LOG_FILE).Length
    $offset  = 0
    $isFirstRun = -not (Test-Path $STATE_FILE)
    if (-not $isFirstRun) {
        try { $offset = [int](Get-Content $STATE_FILE -Raw) } catch { $offset = 0 }
    }

    # ถ้าไฟล์ถูก rotate/truncate (len < offset) → เริ่มใหม่จาก 0 (อ่านทั้งไฟล์)
    if ($fileLen -lt $offset) { $offset = 0 }

    # Overlap: อ่านย้อนจาก offset เล็กน้อย (เจอเหตุการณ์ที่คาบเส้นอ่านจากรอบก่อน)
    $readFrom = [Math]::Max(0, $offset - $OVERLAP)

    if ($fileLen -gt $readFrom) {
        $fs = $null
        try {
            $fs = [System.IO.File]::Open($LOG_FILE, [System.IO.FileMode]::Open,
                                         [System.IO.FileAccess]::Read,
                                         [System.IO.FileShare]::ReadWrite)
            $fs.Seek($readFrom, [System.IO.SeekOrigin]::Begin) | Out-Null
            $reader = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true)
            $newText = $reader.ReadToEnd()
            $reader.Close()
        } catch {
            Write-Host "⚠️ อ่าน agent.log ไม่ได้: $($_.Exception.Message)"
        } finally {
            if ($fs) { $fs.Close() }
        }
        # บันทึก offset ใหม่ (แม้ error ก็เลื่อนไปก่อน กันแจ้งซ้ำ)
        try { Set-Content -Path $STATE_FILE -Value $fileLen -Encoding ASCII } catch { }
    }
}

# ── 2) หาเหตุการณ์ fallback ─────────────────────────────────────
$found = @()
if ($TestSend) {
    $found = @(
        '[TEST] Fallback activated: nvidia/nemotron-3-super-120b-a12b:free → gemini-3.6-flash (gemini)',
        '[TEST] Fallback activated: gemini-3.6-flash → upstage/solar-pro4:free (nous)',
        '[TEST] Fallback activated: upstage/solar-pro4:free → tencent/hy3:free (nous)',
        '[TEST] Fallback activated: tencent/hy3:free → gemini-3.6-flash (gemini)'
    )
} elseif ($newText) {
    $found = @($newText -split "`r?`n" | Where-Object { $_ -match $FALLBACK_PATTERN })
}

# ── 2.1) อ่าน cooldown (เวลาสุดท้ายที่แจ้ง) + บรรทัดที่แจ้งแล้ว ────
$lastAlertUnix = 0
if (Test-Path $COOLDOWN_FILE) {
    try { $lastAlertUnix = [int64](Get-Content $COOLDOWN_FILE -Raw) } catch { }
}
$cooldownSec = $CooldownMinutes * 60
$nowUnix = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

$seen = @()
if (Test-Path $LAST_FILE) {
    try { $seen = @(Get-Content $LAST_FILE | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } catch { }
}

# ── 2.2) ตั้งฉนวนครั้งแรก: จำทุกเหตุการณ์เก่า ไม่ส่ง ──────────────
if ($isFirstRun -and $found.Count -gt 0) {
    $newSeen = @($found | ForEach-Object { ($_ -as [string]).Trim() }) + $seen
    try { Set-Content -Path $LAST_FILE -Value ($newSeen | Select-Object -Last $MAX_LAST) -Encoding UTF8 } catch { }
    try { Set-Content -Path $COOLDOWN_FILE -Value $nowUnix -Encoding ASCII } catch { }
    Write-Host "ℹ️ ครั้งแรก (ตั้งฉนวน) — จำเหตุการณ์เก่า $($found.Count) รายการ ไม่ส่งแจ้งเตือน"
    exit 0
}

# ── 2.3) Dedupe: เหลือเฉพาะเหตุการณ์ที่ยังไม่เคยแจ้ง ──────────────
# (TestSend ข้าม dedupe — ต้องส่งเสมอ ไม่ขึ้นกับ state)
$newFound = if ($TestSend) { @($found) } else { @($found | Where-Object { ($_ -as [string]).Trim() -notin $seen }) }

# ── 2.4) จำเหตุการณ์ใหม่เสมอ (แม้จะอยู่ใน cooldown) — กันแจ้งซ้ำของเดิม
# ใช้ -First เพราะ $newFound + $seen เรียงใหม่-ก่อน → เก็บเหตุการณ์ใหม่สุดไว้ (overlap อ่านซ้ำแค่ส่วนท้าย)
if (-not $TestSend -and $newFound.Count -gt 0) {
    $newSeen = @($newFound | ForEach-Object { ($_ -as [string]).Trim() }) + $seen
    try { Set-Content -Path $LAST_FILE -Value ($newSeen | Select-Object -First $MAX_LAST) -Encoding UTF8 } catch { }
}

# ── 3) ตรวจ cooldown: อยู่ในช่วงเงียบหรือยัง ─────────────────────
$inCooldown = ($nowUnix - $lastAlertUnix) -lt $cooldownSec
if ($TestSend) {
    $inCooldown = $false   # โหมดทดสอบ ข้าม cooldown
}

if ($newFound.Count -eq 0) {
    Write-Host '✅ ไม่พบ fallback ใหม่ (ทุกอย่างปกติ)'
    if ($TestSend) { Write-Host 'ℹ️ โหมดทดสอบ — ต้องเห็นข้อความทดสอบใน Telegram' }
    exit 0
}

if ($inCooldown) {
    $remainMin = [int](($cooldownSec - ($nowUnix - $lastAlertUnix)) / 60)
    Write-Host "ℹ️ อยู่ในช่วงเงียบ (แจ้งล่าสุดเมื่อ $lastAlertUnix) — ไม่แจ้งซ้ำ อีก ~${remainMin} นาทีจึงจะแจ้งใหม่ได้"
    exit 0
}

# มาถึงตรงนี้ = มี fallback ใหม่ + ผ่าน cooldown → ส่ง

# ── 4) สร้างข้อความ (รวมทุกชั้นในรอบนี้ = 1 ข้อความ) ──────────────
$ts = ''
if ($newFound[0] -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') { $ts = $Matches[1] }
if (-not $ts) { $ts = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }

$chainLines = New-Object System.Collections.Generic.List[string]
$chainLines.Add('👀 Fallback Watch')
$chainLines.Add("⚠️ Bot fallback ไปใช้โมเดลสำรอง แล้ว เมื่อ $ts")
$chainLines.Add('')
$chainLines.Add('→ โมเดลหลัก/API มีปัญหา (น่าจะ quota หมด) — ลำดับที่สลับ:')

$i = 0
foreach ($line in $newFound) {
    $i++
    # ตัด prefix ออก เหลือ "X → Y" (ตัด (provider) ท้ายด้วย)
    $step = ($line -as [string]) -replace '^.*?Fallback activated:\s*', ''
    $step = $step -replace '\s*\((openrouter|custom|gemini|nous)\)\s*$', ''
    $layer = if ($step -match 'solar-pro4') { ' (Nous)' }
             elseif ($step -match 'gemini') { ' (Gemini)' } else { '' }
    $chainLines.Add("  $i. $step$layer")
}
$chainLines.Add('')
$chainLines.Add('→ ตอนนี้ตอบผ่านโมเดลสำรอง — คำตอบอาจช้าลง/ตื้นกว่าเดิม')
$chainLines.Add('')
$chainLines.Add("(แจ้งครั้งเดียวต่อ $CooldownMinutes นาที — ไม่สแปม ถ้าตกต่อเนื่อง)")

$body = $chainLines -join "`n"

# ── 4.5) แนบ Health Check ย่อ (เฉพาะ CRIT/WARN) — ระบบเปลี่ยนโมเดล = อยากรู้สถานะรวมด้วย ──
# เรียก health-check.ps1 -Compact (read-only — ไม่แตะ gateway) แล้วเอาเฉพาะบรรทัด CRIT/WARN แนบท้าย
# ถ้าทุกอย่าง OK จะไม่แนบ (กันข้อความรก) — timeout 45 วิ กัน hermes ค้างแล้ว alert ค้างตาม
$hcScript = Join-Path $HERMES_HOME 'health-check.ps1'
if (Test-Path $hcScript) {
    $hcOut = ''
    $hcJob = Start-Job -ScriptBlock {
        param($script)
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Compact 2>&1
    } -ArgumentList $hcScript
    if (Wait-Job $hcJob -Timeout 45) {
        $hcOut = (Receive-Job $hcJob | Out-String).Trim()
    } else {
        Stop-Job $hcJob -ErrorAction SilentlyContinue
    }
    Remove-Job $hcJob -Force -ErrorAction SilentlyContinue

    if ($hcOut) {
        $body += "`n`n🧪 สถานะระบบ (Health Check):`n" + ($hcOut -split "`r?`n" | ForEach-Object { "  $_" }) -join "`n"
    }
}

# ── 5) ส่งแจ้งเตือนผ่าน Telegram Bot API (JSON UTF-8) ─────────────
$sent = $false
$token = ''
try {
    $envText = Get-Content (Join-Path $HERMES_HOME '.env') -Raw -ErrorAction Stop
    $m = [regex]::Match($envText, '(?m)^\s*TELEGRAM_BOT_TOKEN\s*=\s*(\S+)')
    if ($m.Success) {
        $token  = $m.Groups[1].Value
        $chatId = $TelegramTarget.Split(':')[-1]
        $payload = @{ chat_id = $chatId; text = $body } | ConvertTo-Json -Compress
        $bytes   = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $resp = Invoke-RestMethod -Method Post `
            -Uri "https://api.telegram.org/bot$token/sendMessage" `
            -ContentType 'application/json' -Body $bytes -TimeoutSec 20
        $sent = ($resp.ok -eq $true)
        if ($sent) {
            Write-Host "📨 แจ้งเตือน fallback ไป Telegram แล้ว ($($newFound.Count) เหตุการณ์)"
        } else {
            Write-Host '❌ Telegram ตอบ ok=false'
        }
    } else {
        Write-Host '❌ ไม่พบ TELEGRAM_BOT_TOKEN ใน .env'
    }
} catch {
    $errMsg = $_.Exception.Message
    if ($token) { $errMsg = $errMsg -replace [regex]::Escape($token), '[REDACTED]' }
    Write-Host "❌ ส่ง Telegram ไม่สำเร็จ: $errMsg"
}

if ($sent) {
    # บันทึกเวลาที่แจ้ง (สำหรับ cooldown รอบหน้า) — TestSend ไม่เขียน state
    if (-not $TestSend) {
        # (จำเหตุการณ์แล้วใน step 2.4 — ใช้ -First เก็บของใหม่สุด กัน dedupe พลาด)
        try { Set-Content -Path $COOLDOWN_FILE -Value $nowUnix -Encoding ASCII } catch { }
    }
    exit 1
} else { exit 0 }
