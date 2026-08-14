# check-secrets.ps1 — สแกนไฟล์ที่ staged ก่อน commit กัน API key/token หลุด
# วิธีใช้ (รันที่เครื่องไหนก็ได้ก่อน git commit):
#   powershell -ExecutionPolicy Bypass -File check-secrets.ps1
# ถ้าผ่าน: exit 0 (ขึ้น "PASS") / ถ้าเจอ: exit 1 + รายชื่อไฟล์ (ห้าม commit!)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# pattern หลากหลาย: API keys, tokens, JWT, private keys, env assignments
$patterns = @(
    'AIza[0-9A-Za-z_-]{30,}',                      # Google API key
    'sk-[a-z0-9]{20,}',                            # OpenAI/OpenRouter style
    'sk-ant-[a-z0-9]{20,}',                        # Anthropic
    'ghp_[0-9A-Za-z]{30,}', 'gho_[0-9A-Za-z]{30,}','github_pat_[0-9A-Za-z_]{20,}',
    'xox[bap]-[0-9A-Za-z-]{20,}',                  # Slack
    'AKIA[0-9A-Z]{16}',                            # AWS
    '-----BEGIN (RSA|OPENSSH|EC|PRIVATE) KEY-----',
    'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}',  # JWT
    '(GOOGLE_API_KEY|OPENROUTER_API_KEY|TELEGRAM_BOT_TOKEN|GROQ_API_KEY|ANTHROPIC_API_KEY|OPENAI_API_KEY)\s*=\s*[^.<\s][^\s]{8,}'
)

$staged = git diff --cached --name-only 2>$null
if (-not $staged) { Write-Host '✅ PASS — ไม่มีไฟล์ staged' -ForegroundColor Green; exit 0 }

$bad = @()
foreach ($f in $staged) {
    if (-not (Test-Path $f)) { continue }
    foreach ($p in $patterns) {
        if (Select-String -Path $f -Pattern $p -Quiet) {
            $bad += $f
            break
        }
    }
}

if ($bad.Count -gt 0) {
    Write-Host "❌ FAIL — เจอ secret pattern ในไฟล์เหล่านี้ (ห้าม commit!):" -ForegroundColor Red
    $bad | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
    Write-Host "   แก้: ลบไฟล์ออกจาก staging (git rm --cached <file>) หรือเอา key จริงออกก่อน" -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ PASS — ไม่พบ secret pattern ใน staged files ($($staged.Count) ไฟล์)" -ForegroundColor Green
exit 0
