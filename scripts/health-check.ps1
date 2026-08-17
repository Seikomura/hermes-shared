<#
.SYNOPSIS
  🧪 Health Check — ตรวจสุขภาพระบบ Hermes Gateway แบบครบวงจร (ภาษาไทย)

.DESCRIPTION
  ตรวจทีละรายการ:
    1. Heartbeat      — gateway ยัง alive ไหม (updated_at สดหรือเก่า)
    2. Process        — มี hermes.exe / python.exe (gateway) รันอยู่ไหม
    3. Gateway log    — log มีกิจกรรมล่าสุดไหม + เชื่อมต่อ Telegram หรือยัง
    4. Fallback chain — หลัก + fallback ครบไหม (openrouter → nous → gemini — API เท่านั้น)
    5. Tailscale      — VPN เชื่อมต่อไหม (เหลือไว้ตรวจเฉยๆ — ระบบไม่พึ่งเครื่องทำงานอีกแล้ว)
    6. Task Scheduler — HermesGateway / AI_Factory_Gateway เปิด auto-start ไหม
    7. .env keys      — มี GEMINI_API_KEY / OPENROUTER_API_KEY / TELEGRAM_BOT_TOKEN ไหม (ไม่แสดงค่า)
    8. Errors ล่าสุด  — มี error ใหม่ๆ ใน errors.log ไหม

  อ่านเอกสาร workthrough.md สำหรับวิธีแก้ไขเมื่อเจอปัญหา

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File health-check.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File health-check.ps1 -HeartbeatMaxAgeSec 300

.NOTES
  สคริปต์นี้เป็น read-only ไม่แก้ไขอะไรในระบบ
  exit code: 0 = ปกติ / 1 = มีปัญหา (CRIT) / 2 = มีข้อควรสังเกต (WARN)
#>

param(
    [int]$HeartbeatMaxAgeSec = 180,      # heartbeat เก่าเกินเท่าไรถือว่า gateway ตาย (วิ)
    [int]$LogActivityMaxMin   = 10,      # gateway.log นิ่งเกินเท่าไรถือว่าผิดปกติ (นาที)
    [int]$ErrorWindowMin      = 15,      # ดู error ย้อนหลังกี่นาที
    [switch]$NotifyTelegram,             # ส่งผลไป Telegram เมื่อมีปัญหา (CRIT/WARN)
    [switch]$AlwaysReport,               # ส่งผลไป Telegram แม้ปกติ (ใช้ทดสอบ)
    [string]$TelegramTarget = 'telegram:1709297704'   # ปลายทาง (bot:chat_id)
)

$ErrorActionPreference = 'Continue'
$script:startTime = Get-Date

# ── ค่าคงที่ของระบบ (auto-detect — env -> C:\AI Factory -> C:\AI_FACTORY\shared\hermes_home) ──
if ($env:HERMES_HOME -and (Test-Path $env:HERMES_HOME)) { $HERMES_HOME = $env:HERMES_HOME }
elseif (Test-Path 'C:\AI Factory')                       { $HERMES_HOME = 'C:\AI Factory' }
elseif (Test-Path 'C:\AI_FACTORY\shared\hermes_home')    { $HERMES_HOME = 'C:\AI_FACTORY\shared\hermes_home' }
else                                                     { $HERMES_HOME = 'C:\AI Factory' }

$HERMES = $null
foreach ($c in @(
    "$env:LOCALAPPDATA\hermes\hermes-agent\venv\Scripts\hermes.exe",
    "$env:USERPROFILE\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe"
)) { if ($c -and (Test-Path $c)) { $HERMES = $c; break } }
if (-not $HERMES) { $HERMES = 'C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe' }

$env:HERMES_HOME = $HERMES_HOME

# ── ตัวเก็บผลลัพธ์ ─────────────────────────────────────────────────
$script:results = New-Object System.Collections.Generic.List[object]

function Add-Check([string]$Name, [string]$Status, [string]$Detail) {
    $script:results.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail }) | Out-Null
}

function Get-Icon([string]$s) {
    switch ($s) { 'OK' { '✅' } 'WARN' { '⚠️' } 'CRIT' { '❌' } 'INFO' { 'ℹ️' } default { '❓' } }
}

function Get-Color([string]$s) {
    switch ($s) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'CRIT' { 'Red' } default { 'Gray' } }
}

# แยก timestamp "2026-08-10 13:44:16" จากบรรทัด log แล้วเช็คว่าอยู่ใน window หรือไม่
function Test-Recent([string]$Line, [int]$MaxAgeMinutes) {
    if ($Line -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
        try {
            $ts = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss',
                                         [System.Globalization.CultureInfo]::InvariantCulture)
            return (((Get-Date) - $ts).TotalMinutes -lt $MaxAgeMinutes)
        } catch { return $false }
    }
    return $false
}

# ══════════════════════ 1) HEARTBEAT ══════════════════════
$hbPath = Join-Path $HERMES_HOME 'state\gateway.heartbeat'
if (Test-Path $hbPath) {
    try {
        $hb = Get-Content $hbPath -Raw | ConvertFrom-Json
        $hbTime = [datetimeoffset]::Parse($hb.updated_at)
        $ageSec = ([datetimeoffset]::UtcNow - $hbTime).TotalSeconds
        if ($ageSec -lt $HeartbeatMaxAgeSec) {
            Add-Check 'Heartbeat' 'OK' ("สด ({0} วิ, pid={1})" -f [int]$ageSec, $hb.pid)
        } else {
            Add-Check 'Heartbeat' 'CRIT' ("เก่าเกิน ({0} วิ) — gateway อาจตาย/ค้าง" -f [int]$ageSec)
        }
    } catch {
        Add-Check 'Heartbeat' 'CRIT' "อ่านไฟล์ heartbeat ไม่ได้: $($_.Exception.Message)"
    }
} else {
    Add-Check 'Heartbeat' 'CRIT' 'ไม่พบไฟล์ state\gateway.heartbeat — gateway ไม่เคยรัน?'
}

# ══════════════════════ 2) PROCESS ══════════════════════
$gwProcs = @()
try {
    $gwProcs = @(Get-CimInstance Win32_Process -Filter "Name='hermes.exe' OR Name='python.exe'" |
                 Where-Object { $_.CommandLine -match 'hermes' -and $_.CommandLine -match 'gateway' })
} catch { }
if ($gwProcs.Count -gt 0) {
    $pids = ($gwProcs | ForEach-Object { $_.ProcessId }) -join ', '
    Add-Check 'Process' 'OK' "พบ gateway $($gwProcs.Count) process (pid: $pids)"
} else {
    Add-Check 'Process' 'CRIT' 'ไม่พบ hermes/python gateway process — gateway ไม่รัน!'
}

# ══════════════════════ 2.5) TELEGRAM IPv4 PROXY ══════════════════════
# proxy (telegram-ipv4-proxy.py, port 8899) ตาย = Telegram ต่อไม่ได้ทั้งที่ gateway ยังปกติ
# -> ต้องเช็คทุกครั้ง (ถ้าตาย HealthCheck จะแจ้งเตือน + ระบบอื่น (gateway-watch) จะ start กลับเอง)
$proxyOk = $false
try {
    $pc = New-Object Net.Sockets.TcpClient
    $pc.Connect('127.0.0.1', 8899)
    $pc.Close()
    $proxyOk = $true
} catch { }
if ($proxyOk) {
    Add-Check 'Telegram proxy' 'OK' 'port 8899 ฟังอยู่ (telegram-ipv4-proxy.py ทำงาน)'
} else {
    Add-Check 'Telegram proxy' 'CRIT' 'port 8899 ตาย! proxy (telegram-ipv4-proxy.py) ไม่รัน — Telegram จะต่อไม่ได้; gateway-watch จะ start กลับเองภายใน 2 นาที'
}

# ══════════════════════ 3) GATEWAY LOG ══════════════════════
$gwLog = Join-Path $HERMES_HOME 'logs\gateway.log'
if (Test-Path $gwLog) {
    $lastLine = Get-Content $gwLog -Tail 1
    if ($lastLine -and (Test-Recent $lastLine $LogActivityMaxMin)) {
        Add-Check 'Gateway log' 'OK' "มีกิจกรรมล่าสุด (< $LogActivityMaxMin นาที)"
    } else {
        # เงียบนาน = ปกติ ถ้าไม่มีใครคุย (หัวใจสำคัญคือ heartbeat ที่เช็คไปแล้ว)
        Add-Check 'Gateway log' 'INFO' 'ไม่มีข้อความล่าสุด (ปกติ ถ้าไม่มีใครคุยกับ bot)'
    }
    $conn = Select-String -Path $gwLog -Pattern 'telegram connected' | Select-Object -Last 1
    if ($conn) {
        Add-Check 'Telegram' 'INFO' 'เคยเชื่อมต่อ Telegram แล้ว (ดูเวลาใน gateway.log)'
    } else {
        Add-Check 'Telegram' 'WARN' 'ยังไม่เคยเห็น "telegram connected" ใน gateway.log'
    }
} else {
    Add-Check 'Gateway log' 'CRIT' 'ไม่พบ logs\gateway.log'
}

# ══════════════════════ 4) FALLBACK CHAIN ══════════════════════
# รัน hermes fallback list แบบมี timeout (กันกรณี hermes ค้างแล้วสคริปต์ค้างตาม)
$fb = ''
if (Test-Path $HERMES) {
    $fbJob = Start-Job -ScriptBlock {
        param($h, $hh)
        $env:HERMES_HOME = $hh
        & $h fallback list 2>&1 | Out-String
    } -ArgumentList $HERMES, $HERMES_HOME
    if (Wait-Job $fbJob -Timeout 20) {
        $fb = (Receive-Job $fbJob)
    } else {
        Stop-Job $fbJob -ErrorAction SilentlyContinue
    }
    Remove-Job $fbJob -Force -ErrorAction SilentlyContinue
}
if ($fb) {
    $okGemini     = $fb -match 'gemini'
    $okNous       = $fb -match 'solar-pro4'
    $okOpenRouter = $fb -match 'nemotron'
    if ($okGemini -and $okNous -and $okOpenRouter) {
        Add-Check 'Fallback chain' 'OK' 'หลัก openrouter (nemotron) + fallback ครบ (nous → gemini)'
    } else {
        $missing = @()
        if (-not $okOpenRouter) { $missing += 'openrouter (nemotron)' }
        if (-not $okNous)       { $missing += 'nous (solar-pro4)' }
        if (-not $okGemini)     { $missing += 'gemini' }
        Add-Check 'Fallback chain' 'WARN' ("ไม่ครบ/ผิดปกติ: ขาด {0}" -f ($missing -join ', '))
        Add-Check 'Fallback chain' 'INFO' 'รัน "hermes fallback list" เพื่อดูรายละเอียด'
    }
} elseif (-not (Test-Path $HERMES)) {
    Add-Check 'Fallback chain' 'CRIT' "ไม่พบ hermes.exe ที่ $HERMES"
} else {
    Add-Check 'Fallback chain' 'WARN' 'hermes fallback list ไม่ตอบภายใน 20 วิ (hermes อาจค้าง)'
}# ══════════════════════ 5) TAILSCALE ══════════════════════
# ระบบเป็น API-only แล้ว (v12) — ไม่ต้องพึ่งเครื่องทำงาน/LM Studio; เช็คไว้เฉยๆ เป็น INFO
$tsExe = 'C:\Program Files\Tailscale\tailscale.exe'
if (Test-Path $tsExe) {
    $tsIp = (& $tsExe ip -4 2>&1 | Select-Object -First 1)
    if ($tsIp -match '^100\.') {
        Add-Check 'Tailscale' 'INFO' "เชื่อมต่อ (IP: $tsIp) — ไม่ได้ใช้กับ chain อีกแล้ว (API-only)"
    } else {
        Add-Check 'Tailscale' 'INFO' "tailscale ไม่ตอบ IP: $tsIp — ไม่กระทบ (API-only)"
    }
} else {
    Add-Check 'Tailscale' 'INFO' 'ไม่พบ tailscale.exe — ไม่กระทบ (API-only)'
}

# ══════════════════════ 6) TASK SCHEDULER ══════════════════════
# รองรับทั้ง task HermesGateway (เครื่องทำงาน) และ AI_Factory_Gateway (เครื่องบ้าน)
$taskOut = (schtasks /query /TN HermesGateway /V /FO LIST 2>&1 | Out-String)
if ($taskOut -match 'is not currently running|ERROR|ไม่พบ') {
    $taskOut2 = (schtasks /query /TN AI_Factory_Gateway /V /FO LIST 2>&1 | Out-String)
    if ($taskOut2 -match 'is not currently running|ERROR|ไม่พบ') {
        Add-Check 'Auto-start task' 'CRIT' 'ไม่พบ task HermesGateway / AI_Factory_Gateway — จะไม่ start ตอนเปิดเครื่อง!'
    } else {
        Add-Check 'Auto-start task' 'OK' 'AI_Factory_Gateway (เครื่องบ้าน) มีอยู่ — gateway จะ start ตอน login'
    }
} else {
    $atStartup = $taskOut -match 'At system start up|At log on'
    $status    = if ($taskOut -match 'Status:\s+(\w+)') { $Matches[1] } else { '?' }
    if ($atStartup) {
        Add-Check 'Auto-start task' 'OK' "HermesGateway — trigger เปิดเครื่อง/login + สถานะ $status"
    } else {
        Add-Check 'Auto-start task' 'WARN' "HermesGateway trigger ผิดปกติ (ตอนนี้: สถานะ $status)"
    }
}

# ══════════════════════ 7) .env KEYS (ชื่อเท่านั้น!) ══════════════════════
$envFile = Join-Path $HERMES_HOME '.env'
if (Test-Path $envFile) {
    $envTxt = Get-Content $envFile -Raw
    # Gemini key: ยอมรับทั้ง GEMINI_API_KEY (เครื่องบ้าน) และ GOOGLE_API_KEY (เครื่องทำงาน)
    $gKey = if ($envTxt -match '(?m)^\s*(?:GEMINI|GOOGLE)_API_KEY\s*=\s*\S') { 'OK' } else { 'CRIT' }
    $oKey = if ($envTxt -match '(?m)^\s*OPENROUTER_API_KEY\s*=\s*\S') { 'OK' } else { 'CRIT' }
    $tKey = if ($envTxt -match '(?m)^\s*TELEGRAM_BOT_TOKEN\s*=\s*\S') { 'OK' } else { 'CRIT' }
    Add-Check '.env: Gemini key' $gKey $(if ($gKey -eq 'OK') { 'ตั้งค่าแล้ว (ซ่อนค่า)' } else { 'ยังไม่ตั้งค่า — GEMINI_API_KEY หรือ GOOGLE_API_KEY (ดู README.md ส่วน .env)' })
    Add-Check '.env: OpenRouter' $oKey $(if ($oKey -eq 'OK') { 'ตั้งค่าแล้ว (ซ่อนค่า)' } else { 'ยังไม่ตั้งค่า — ดู README.md ส่วน .env' })
    Add-Check '.env: Telegram' $tKey $(if ($tKey -eq 'OK') { 'ตั้งค่าแล้ว (ซ่อนค่า)' } else { 'ยังไม่ตั้งค่า — ดู README.md ส่วน .env' })
} else {
    Add-Check '.env' 'CRIT' "ไม่พบไฟล์ .env ที่ $HERMES_HOME"
}

# ══════════════════════ 8) ERRORS ล่าสุด ══════════════════════
$errLog = Join-Path $HERMES_HOME 'logs\errors.log'
if (Test-Path $errLog) {
    $recentErrs = @()
    foreach ($line in (Get-Content $errLog -Tail 800)) {
        # นับเฉพาะ error ระดับ ERROR/CRITICAL (ดูที่ level field หลัง timestamp) + Traceback
        # ไม่นับ WARNING ของ tool ปกติ (เช่น terminal returned error)
        $isErrorLevel = $line -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d+\s+(ERROR|CRITICAL)'
        if (($isErrorLevel -or ($line -match 'Traceback')) -and (Test-Recent $line $ErrorWindowMin)) {
            $recentErrs += $line
        }
    }
    if ($recentErrs.Count -gt 0) {
        $lastErr = $recentErrs[-1] -replace '([A-Za-z0-9_-]{12,})', '<redacted>'
        if ($lastErr.Length -gt 160) { $lastErr = $lastErr.Substring(0, 160) + '...' }
        Add-Check "Errors (${ErrorWindowMin}นาที)" 'WARN' "$($recentErrs.Count) จุด — ล่าสุด: $lastErr"
    } else {
        Add-Check "Errors (${ErrorWindowMin}นาที)" 'OK' 'ไม่มี error ใหม่'
    }
} else {
    Add-Check 'Errors' 'INFO' 'ไม่พบ logs\errors.log'
}

# ══════════════════════ 10) PYTHON DEPS (venv) ══════════════════════
# ตรวจว่า venv ของ Hermes import ครบไหม — กันเหตุการณ์ pydantic หายแล้ว bot เงียบ
# (heartbeat ยังสด แต่ทุกข้อความล้มตอน init agent — เจอจริง 14 ส.ค. 69: bot รัน pip install
#  แล้วโดนตัดกลางคัน -> pydantic หาย -> openai import ไม่ได้)
$VENV_PY = 'C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe'
if (Test-Path $VENV_PY) {
    $depJob = Start-Job -ScriptBlock {
        param($py)
        & $py -c "import pydantic, pydantic.fields; from openai import OpenAI; print('OK', pydantic.VERSION)" 2>&1 | Out-String
    } -ArgumentList $VENV_PY
    $depOut = ''
    if (Wait-Job $depJob -Timeout 25) {
        $depOut = (Receive-Job $depJob)
    } else {
        Stop-Job $depJob -ErrorAction SilentlyContinue
    }
    Remove-Job $depJob -Force -ErrorAction SilentlyContinue
    if ($depOut -match 'OK') {
        $ver = if ($depOut -match 'OK (\d+\.\d+)') { $Matches[1] } else { '?' }
        Add-Check 'Python deps' 'OK' ("venv import ครบ (pydantic {0}, openai OK)" -f $ver)
    } else {
        $hint = 'ซ่อม: uv pip install --python "' + $VENV_PY + '" "pydantic==2.13.4" แล้ว restart gateway'
        Add-Check 'Python deps' 'CRIT' "venv พัง (pydantic/openai import ไม่ได้) — $hint"
    }
} else {
    Add-Check 'Python deps' 'INFO' 'ไม่พบ venv python.exe'
}

# ══════════════════════ REPORT ══════════════════════
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  🧪 HEALTH CHECK — Hermes Gateway System" -ForegroundColor Cyan
Write-Host ("  " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$nCrit = 0; $nWarn = 0
$reportLines = New-Object System.Collections.Generic.List[string]
foreach ($r in $script:results) {
    if ($r.Status -eq 'CRIT') { $nCrit++ }
    if ($r.Status -eq 'WARN') { $nWarn++ }
    $icon  = Get-Icon $r.Status
    $color = Get-Color $r.Status
    $line  = "{0} {1,-22} : {2}" -f $icon, $r.Name, $r.Detail
    $reportLines.Add($line)
    Write-Host $line -ForegroundColor $color
}

Write-Host ""
Write-Host "────────────────────────────────────────────────────────" -ForegroundColor DarkGray
if ($nCrit -gt 0) {
    Write-Host "ผลสรุป: ❌ มีปัญหา $nCrit จุด (ควรแก้ทันที) — ดู workthrough.md ส่วนที่เกี่ยวข้อง" -ForegroundColor Red
} elseif ($nWarn -gt 0) {
    Write-Host "ผลสรุป: ⚠️ ปกติโดยรวม แต่มี $nWarn จุดที่ควรสังเกต" -ForegroundColor Yellow
} else {
    Write-Host "ผลสรุป: ✅ ระบบปกติทั้งหมด" -ForegroundColor Green
}
Write-Host ("เวลาในการตรวจ: {0} วินาที" -f [int]((Get-Date) - $script:startTime).TotalSeconds) -ForegroundColor DarkGray
Write-Host "────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ══════════════════════ TELEGRAM แจ้งเตือน ══════════════════════
# ส่งผลไป Telegram ผ่าน `hermes send` (ใช้ key เดียวกับ bot ไม่ต้องเปิด gateway)
# ส่งเมื่อ: มี CRIT/WARN หรือระบุ -AlwaysReport
if ($NotifyTelegram) {
    $statusEmoji = if ($nCrit -gt 0) { '❌' } elseif ($nWarn -gt 0) { '⚠️' } else { '✅' }
    $statusText  = if ($nCrit -gt 0)  { 'มีปัญหา! ดู workthrough.md' }
                   elseif ($nWarn -gt 0) { 'ปกติโดยรวม แต่มีข้อควรสังเกต' }
                   else { 'ปกติทั้งหมด' }
    $msgLines = New-Object System.Collections.Generic.List[string]
    $msgLines.Add("🧪 Health Check — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $msgLines.Add("สถานะ: $statusEmoji $statusText")
    $msgLines.Add('')
    foreach ($line in $reportLines) { $msgLines.Add($line) }
    $body = $msgLines -join "`n"

    if (($nCrit -gt 0) -or ($nWarn -gt 0) -or $AlwaysReport) {
        # ส่งผ่าน Telegram Bot API ตรงๆ ด้วย JSON UTF-8 (การันตีภาษาไทยไม่เพี้ยน)
        # อ่าน token จาก .env แบบไม่โชว์ค่า — ใช้ได้แม้ gateway/CLI จะพัง
        $sent = $false
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
                    Write-Host "📨 แจ้งเตือนไป Telegram แล้ว ($TelegramTarget)" -ForegroundColor Cyan
                } else {
                    Write-Host "❌ Telegram ตอบ ok=false" -ForegroundColor Red
                }
            } else {
                Write-Host '❌ ไม่พบ TELEGRAM_BOT_TOKEN ใน .env' -ForegroundColor Red
            }
        } catch {
            $errMsg = $_.Exception.Message
            if ($token) { $errMsg = $errMsg -replace [regex]::Escape($token), '[REDACTED]' }
            Write-Host "❌ ส่ง Telegram ไม่สำเร็จ: $errMsg" -ForegroundColor Red
        }
    } else {
        Write-Host "(ระบบปกติ — ไม่ส่งข้อความ ใช้ -AlwaysReport เพื่อทดสอบส่ง)" -ForegroundColor DarkGray
    }
}

# exit code สำหรับ automation: 0 = OK, 2 = WARN, 1 = CRIT
if ($nCrit -gt 0) { exit 1 } elseif ($nWarn -gt 0) { exit 2 } else { exit 0 }
