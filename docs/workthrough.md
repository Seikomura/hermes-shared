# 🔧 Workthrough — คู่มือแก้ปัญหาด้วยตัวเอง

> เอกสารนี้รวมทุกปัญหาที่เคยเจอ + วิธีแก้ทีละขั้นตอน
> **หลักการ:** เช็ค → วินิจฉัย → แก้ → ตรวจผล เสมอ
> ถ้า Telegram ใช้ไม่ได้ → ข้ามไป [ส่วน D: ใช้ CLI ฉุกเฉิน](#d-ใช้-cli-ฉุกเฉินเมื่อ-telegram-ใช้ไม่ได้)

---

## 🧰 เตรียมตัวก่อน (รัน 1 ครั้งทุก PowerShell)

```powershell
$HERMES = 'C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe'
$env:HERMES_HOME = 'C:\AI Factory'
```

---

## ⚡ สายด่วน: เช็คสุขภาพใน 30 วินาที

**วิธีที่เร็วที่สุด — รันสคริปต์ตรวจสุขภาพ 1 คำสั่ง:**
```powershell
powershell -ExecutionPolicy Bypass -File 'C:\AI Factory\health-check.ps1'
```
ตรวจครบ 8 จุด: heartbeat, process, gateway log, fallback chain (API-only), Tailscale, auto-start task, .env keys, errors — รายงานเป็นภาษาไทยพร้อมสี (exit code: 0=ปกติ / 1=มีปัญหา / 2=มีข้อควรสังเกต)

> 📌 **ถ้าแก้ไฟล์ `health-check.ps1` แล้วรันไม่ได้ (error parse ตอนภาษาไทย)** — ไฟล์ต้องเป็น **UTF-8 with BOM** ไม่งั้น PowerShell 5.1 อ่านภาษาไทยเพี้ยน ให้เปิดด้วย editor ที่เซฟเป็น UTF-8 with BOM (หรือ Notepad → Save As → Encoding: UTF-8 with BOM)

**หรือเช็คมือ (ถ้าอยากเห็น raw data):**
```powershell
# 1) Gateway ยัง alive ไหม? (ดู updated_at ว่าสดหรือเก่า)
Get-Content 'C:\AI Factory\state\gateway.heartbeat'

# 2) Process ทำงานไหม? (ควรเห็น hermes.exe + python.exe)
tasklist | findstr /i "hermes python"

# 3) เชื่อมต่อ Telegram หรือยัง?
& $HERMES logs gateway -n 10

# 4) มี error อะไรล่าสุด?
& $HERMES logs errors -n 15
```

**แปลผล:**
- heartbeat `updated_at` เก่าเกิน 2-3 นาที + ไม่มี process → **gateway ตาย** → ไป [ส่วน restart](#วิธี-restart-gateway)
- heartbeat สด + process มี แต่ bot ไม่ตอบ → อ่าน [ส่วน A](#a-bot-ไม่ตอบเงียบ)
- มี `429` / `RESOURCE_EXHAUSTED` → อ่าน [ส่วน B](#b-error-429--quota-หมด)

---

## 📖 รู้จัก log (ไฟล์อะไรอยู่ไหน)

| ไฟล์ | ดูอะไร | วิธีอ่าน |
|---|---|---|
| `logs\gateway.log` | รับ/ส่งข้อความ, เชื่อมต่อ Telegram | `& $HERMES logs gateway -n 50` |
| `logs\agent.log` | API calls, tool calls, fallback, เวลาตอบ | `& $HERMES logs -n 100` |
| `logs\errors.log` | error/exception ทั้งหมด | `& $HERMES logs errors -n 30` |
| `gateway-console.log` | console output (ตอนนี้ output ทั้งหมดไปไฟล์นี้) | `Get-Content 'C:\AI Factory\gateway-console.log' -Tail 30` |
| `state\gateway.heartbeat` | สัญญาณหัวใจ (alive ไหม) | `Get-Content 'C:\AI Factory\state\gateway.heartbeat'` |

**คำศัพท์ที่เจอบ่อยใน log:**
- `API call failed (attempt 1/3) error_type=GeminiAPIError` → เรียก API ไม่สำเร็จ (กำลัง retry)
- `Retrying API call in Xs` → รอ retry (ถ้าเป็น 429 จะรอ ~20-30 วิ)
- `switching to fallback provider` → กำลังสลับไปโมเดลสำรอง ✅
- `response ready: ... time=8.4s` → ตอบสำเร็จ + เวลาที่ใช้
- `thread=bg-review` → งาน background (จำความ) ไม่เกี่ยวกับการตอบผู้ใช้

---

## 🔄 วิธี restart gateway (วิธีมาตรฐาน)

```powershell
# 1) ปิด gateway
schtasks /end /TN HermesGateway 2>$null
taskkill /F /IM hermes.exe 2>$null
Start-Sleep 3

# 2) ลบ pid/lock ค้าง (ถ้าไม่ลบ อาจรันซ้ำไม่ได้)
Remove-Item 'C:\AI Factory\gateway.pid','C:\AI Factory\gateway.lock' -Force -ErrorAction SilentlyContinue

# 3) เปิดใหม่
schtasks /run /TN HermesGateway

# 4) รอ ~60 วินาที แล้วเช็ค
Start-Sleep 60
Get-Content 'C:\AI Factory\state\gateway.heartbeat'
& $HERMES logs gateway -n 5
```

**ผลลัพธ์ที่ถูกต้อง:** heartbeat `updated_at` สด + เห็น `✓ telegram connected` ใน gateway.log

> ⚠️ ถ้า `schtasks /run` บอก "currently running" = task instance ค้างอยู่ → รัน `schtasks /end /TN HermesGateway` ก่อน แล้วค่อย `/run` ใหม่
> ⚠️ หลัง restart ข้อความที่ค้างไว้อาจถูกประมวลผลใหม่ช้า (bot จะค่อยๆ ตอบ) — รอสัก 1-2 นาที

---

## 🐛 ปัญหาที่พบบ่อย

### A. Bot ไม่ตอบ / เงียบ

**ขั้นที่ 1 — เช็คว่า gateway ตายหรือค้าง:**
```powershell
Get-Content 'C:\AI Factory\state\gateway.heartbeat'   # updated_at สดไหม?
tasklist | findstr /i "hermes python"                  # มี process ไหม?
```

> ✅ **ตอนนี้มี watchdog แล้ว 2 ชั้น:** (1) `HermesGatewayLogonKick` — รัน `gateway-watch.ps1` **ทันทีที่ login** ถ้า gateway ตายค้างจากคืนก่อน (2) `HermesGatewayWatch` — รัน **ทุก 2 นาที** (ทั้งคู่ผ่าน hidden-runner.vbs ไร้หน้าต่าง) — เช็ค heartbeat ถ้าเก่าเกิน 4 นาที (gateway ตาย/ค้าง) → **restart ให้อัตโนมัติ** กัน "bot เงียบ" ซ้ำๆ (log: `C:\AI Factory\logs\gateway-watch.log`) — โดยปกติไม่ต้องทำอะไรด้วยมือ รอ ~2 นาที bot จะกลับมาเอง

**กรณีที่ 1: ไม่มี process + heartbeat เก่า** → gateway ตาย → restart ตาม [วิธีมาตรฐาน](#วิธี-restart-gateway) (หรือรอ watchdog restart ให้)

**กรณีที่ 2: มี process + heartbeat สด แต่ไม่ตอบ** → ดูว่า turn ค้างหรือเปล่า:
```powershell
Get-Content 'C:\AI Factory\gateway-console.log' -Tail 20   # log หยุดนิ่งที่บรรทัดไหน?
& $HERMES logs errors -n 20
```
- ถ้าเห็น error/crash → restart
- ถ้า log นิ่งสนิท + process ยังมี (CPU นิ่ง) → **turn ค้าง** → restart (วิธีมาตรฐาน)

> 📌 **ประวัติ:** เคยเจอ bot เงียบ 15 นาทีเพราะ `gw-hidden.ps1` เก่า redirect stdout/stderr ไป **pipe ที่ไม่มีใครอ่าน** → pipe เต็ม → thread ค้างที่ logging ตลอดไป ตอนนี้แก้แล้ว (redirect ไปไฟล์ `gateway-console.log` แทน) — **ห้าม revert** การแก้นี้
> 📌 gateway ยังทำงานได้ (heartbeat สด) แม้ turn จะค้าง — เช็คที่ console log ว่ามันค้างตรงไหนเสมอ

---

### B. Error 429 / quota หมด

**อาการ:** bot ตอบ error `Gemini HTTP 429 (RESOURCE_EXHAUSTED): You exceeded your current quota...`

**สาเหตุ:** Gemini free tier = **20 request/นาที** — เทิร์นที่ต้องเรียก API หลายครั้ง (tool calls) จะกิน quota เร็ว

**วิธีแก้:**
1. **ไม่ต้องทำอะไร** — quota reset เองใน ~1 นาที (rolling window) ระบบจะตอบได้อีก
2. ระหว่างนั้น Hermes จะ **fallback อัตโนมัติ** ไป gemini-3.6-flash/gemma:free (ดูจาก log: `switching to fallback provider`)
3. ถ้าอยากให้ Gemini เป็นหลักแบบไม่สะดุดจริงๆ → เปิด billing ที่ [Google AI Studio](https://aistudio.google.com/apikey) (ใช้ key ที่ผูกบัญชีเสียเงิน) แล้วเปลี่ยน `GOOGLE_API_KEY` ใน `.env` → restart

**ตรวจว่า fallback ทำงาน:**
```powershell
& $HERMES fallback list          # หลัก + chain ครบ 3 ตัวไหม?
# ทดสอบแต่ละตัวตรงๆ ผ่าน CLI:
& $HERMES chat -q 'ตอบว่า OK' -Q --provider openrouter -m nvidia/nemotron-3-super-120b-a12b:free --max-turns 2
& $HERMES chat -q 'ตอบว่า OK' -Q --provider gemini -m gemini-3.6-flash --max-turns 2
```

---

### C. ตอบช้า

**วิธีวิเคราะห์:** ดู `agent.log` ว่าใช้เวลาที่ไหน
```powershell
& $HERMES logs -n 100 | findstr "API call Turn ended response"
```

- `response ready: time=8.4s api_calls=1` → ปกติ (เร็ว)
- `Retrying API call in Xs` เยอะๆ → กำลังเจอ 429 แล้วรอ retry (~20-30 วิ/รอบ) → fallback จะช่วย
- `API call failed (attempt 1/3)` ครบ 3 รอบ → ตกไป fallback (ช้าสักหน่อยแต่ตอบได้)
- latency สูงทุกครั้ง (20-80 วิ) → โมเดลรอง/fallback ช้าธรรมชาติ หรือเน็ตช้า

**แก้:** ถ้า Gemini quota ชนบ่อย → เปิด billing (ส่วน B) หรือใช้โมเดลที่เร็วกว่า

---

### D. ใช้ CLI ฉุกเฉิน (เมื่อ Telegram ใช้ไม่ได้) ⭐

**เมื่อไรที่ควรใช้:** Telegram bot ไม่ตอบ / เน็ตโทรศัพท์มีปัญหา / อยากสั่งงานเครื่องโดยตรง
**ข้อดี:** ใช้ config + key เดียวกันกับ bot ทุกอย่าง — แก้ปัญหา/เทสต์ได้ครบ

```powershell
# ── ทดสอบระบบพื้นฐาน ──
& $HERMES status                          # key ครบไหม, โมเดลอะไร
& $HERMES fallback list                   # fallback chain ครบไหม

# ── ถามคำถามครั้งเดียว (สำคัญ: เติม -Q เพื่อ output สั้นๆ) ──
& $HERMES chat -q 'สวัสดี ตอบสั้นๆ 1 ประโยค' -Q --max-turns 3

# ── บังคับใช้โมเดลแต่ละตัว (เทสต์ว่าตัวไหนพัง) ──
& $HERMES chat -q 'ตอบว่า OK' -Q --provider gemini -m gemini-3.6-flash --max-turns 2
& $HERMES chat -q 'ตอบว่า OK' -Q --provider openrouter -m nvidia/nemotron-3-super-120b-a12b:free --max-turns 2
& $HERMES chat -q 'ตอบว่า OK' -Q --provider openrouter -m google/gemma-4-31b-it:free --max-turns 2
& $HERMES chat -q 'ตอบว่า OK' -Q --provider nous -m upstage/solar-pro4:free --max-turns 2
& $HERMES chat -q 'ตอบว่า OK' -Q --provider gemini -m gemini-3.6-flash --max-turns 2

# ── โหมดโต้ตอบ (พิมพ์คุยเรื่อยๆ) ──
& $HERMES chat

# ── ดู log เพื่อวินิจฉัย ──
& $HERMES logs gateway -n 50
& $HERMES logs errors -n 30
```

**ตารางเทสต์:** ถ้า `--provider X` ไม่ตอบ/error → แสดงว่าตัวนั้นมีปัญหา → ดูส่วนที่เกี่ยวข้อง (B/G/F)

> 💡 (v12 — ลบ LM Studio แล้ว) ระบบเป็น API-only: ทดสอบแต่ละชั้นด้วย `--provider openrouter` / `--provider nous` / `--provider gemini`

> 💡 ใช้ `--max-turns 2-3` เสมอตอนเทสต์ เพื่อไม่ให้ agent รัน tool เป็นชุดยาวๆ กิน quota/เวลา

---

### E. Gateway ไม่ start หลังเปิดเครื่อง

```powershell
# task มีไหม + trigger อะไร?
schtasks /query /TN HermesGateway /V /FO LIST

# ลอง start ด้วยมือ
schtasks /run /TN HermesGateway
Start-Sleep 60
Get-Content 'C:\AI Factory\state\gateway.heartbeat'
```

**ถ้ายังไม่ขึ้น:**
1. ตรวจ `C:\AI Factory\gateway-console.log` (output ทั้งหมดไปไฟล์นี้ — ถ้าว่างแปลว่า hermes ไม่เคย start)
2. ตรวจว่ามี wscript ค้าง (watcher วน loop) → `taskkill /F /IM wscript.exe` แล้ว `/run` ใหม่
3. ตรวจ `.env` ว่ามี `TELEGRAM_BOT_TOKEN` หรือไม่ → ถ้าไม่มี bot เชื่อมต่อไม่ได้ (แต่ CLI ยังใช้ได้)

---

### F. Local AI / LM Studio (ถูกลบออกแล้วตั้งแต่ v12 — 17 ส.ค. 2026)

> ⚠️ ระบบเป็น **API-only** แล้ว (chain 12 ชั้น: OpenRouter × 8 → Nous × 3 → Gemini) — LM Studio (เครื่องนี้ + เครื่องทำงานผ่าน Tailscale) **ถูกถอดออกจาก config แล้ว** ไฟล์ `lmstudio-watch.ps1` / `lmstudio-alert.py` / `work-lmstudio-autostart.ps1` / `lmstudio-start.ps1` ถูกลบ — **ไม่ต้องเปิด LM Studio / Tailscale / เครื่องทำงานอีก**
> ถ้าเจอ error เกี่ยวกับ qwen3.5-9b / qwen3-1.7b / port 1234 / 100.77.88.33 → มองข้ามได้ (เป็น config เก่าที่โดนลบแล้ว) — ตรวจ `hermes fallback list` ว่ามีแค่ 12 ชั้น API

---

### K. (ถูกลบแล้ว — เคยเป็น Error: `"qwen3.5-9b" does not support thinking`)

> ⚠️ ระบบเป็น API-only (v12) — โมเดล local qwen3.5-9b/qwen3-1.7b ถูกลบจาก config แล้ว ปัญหา reasoning ของโมเดล local นี้ไม่มีอีกต่อไป

---

### H. หน้าต่าง terminal ปริศนา

| หน้าต่างที่เห็น | ปิดได้ไหม? |
|---|---|
| Windows Terminal เปล่า (เปิดค้างตั้งแต่เช้า) | ✅ ปิดได้ (ไม่ใช่ bot) |
| cmd เปล่า title ว่าง | ✅ ปิดได้ถ้าไม่ใช่ตัวที่กำลังรันคำสั่ง |
| หน้าต่าง "gateway started pid=..." | ⚠️ ตัวจริง bot รันแบบ **ไม่มีหน้าต่าง** — ถ้าเห็นแบบนี้เป็นของเก่า/หลงเหลือ ปิดได้ แล้วตรวจ gateway ยังตอบไหม |

**ตรวจว่าการปิดหน้าต่างไม่กระทบ bot:**
```powershell
Get-Content 'C:\AI Factory\state\gateway.heartbeat'   # ยังสดไหม?
```
> bot ปกติจะรันเงียบๆ ไม่มีหน้าต่างเด็ดขาด (สร้างด้วย CREATE_NO_WINDOW) — ถ้าเห็นหน้าต่างโผล่ทุกครั้ง แปลว่ามีปัญหาที่ launcher

---

### I. แก้ .env / config แล้วไม่มีผล

**ต้อง restart gateway ทุกครั้ง** หลังแก้ไฟล์ config ใดๆ:
```powershell
schtasks /end /TN HermesGateway 2>$null
taskkill /F /IM hermes.exe 2>$null
Start-Sleep 3
schtasks /run /TN HermesGateway
```
> CLI (`hermes chat`) อ่าน config ใหม่ทุกครั้งที่รัน — ถ้าอยากเทสต์ config ใหม่ไวๆ ใช้ CLI ก่อน restart ก็ได้

---

### J. (ถูกลบแล้ว — เคยเป็น: เครื่องบ้านต่อกับเครื่องทำงานผ่าน Tailscale)

> ⚠️ v12 — ไม่ต้องใช้ Tailscale / เครื่องทำงาน / LM Studio อีกแล้ว (API-only) — ข้ามหัวข้อนี้ได้

---

## 📋 ตารางคำสั่ง CLI ที่ใช้บ่อย

| คำสั่ง | ใช้ทำอะไร |
|---|---|
| `powershell -File health-check.ps1` | ตรวจสุขภาพครบ 8 จุด (รันจาก `C:\AI Factory`) |
| `... health-check.ps1 -NotifyTelegram` | ตรวจ + ส่งผลไป Telegram เฉพาะตอนมีปัญหา |
| `... health-check.ps1 -NotifyTelegram -AlwaysReport` | ตรวจ + ส่งผลไป Telegram เสมอ (ทดสอบ) |
| `schtasks /query /TN HermesHealthCheck /V /FO LIST` | เช็ค task ตรวจสุขภาพ (ทุก 30 นาที) |
| `& $HERMES status` | สถานะรวม (โมเดล, keys, .env) |
| `& $HERMES fallback list` | ดู fallback chain |
| `& $HERMES chat -q '...' -Q --max-turns 3` | ถามครั้งเดียว (ฉุกเฉิน) |
| `& $HERMES chat` | โหมดโต้ตอบ |
| `& $HERMES logs gateway -n 50` | ดู log gateway |
| `& $HERMES logs errors -n 30` | ดู error |
| `& $HERMES logs -f` | ตาม log real-time |
| `schtasks /query /TN HermesGateway /V /FO LIST` | ดูสถานะ task auto-start |
| `schtasks /run /TN HermesGateway` | เปิด gateway |
| `schtasks /end /TN HermesGateway` | ปิด gateway |
| `taskkill /F /IM hermes.exe` | ฆ่า gateway process |
| `tailscale status` | เช็ค Tailscale (ไม่จำเป็นแล้ว — API-only v12) |

> 💻 หมายเหตุ: ถ้าใช้ **git-bash** แทน PowerShell ให้เปลี่ยน `/` เป็น `//` (เช่น `schtasks //run //TN HermesGateway`)

---

## 👀 Fallback Watch — แจ้งเตือนเมื่อ bot fallback (ทุกชั้น, แบบไม่สแปม)

Task **`HermesFallbackWatch`** รัน `fallback-watch.ps1` ทุก 1 นาที

**แจ้งเตือนเมื่อ:** bot fallback ไปโมเดลสำรอง **ชั้นใดก็ได้** (openrouter → nous → gemini) — chain ล้มพร้อมกันหลายชั้นจะ**รวมเป็นข้อความเดียว**พร้อมลำดับ

**กันสแปม (cooldown):** แจ้งครั้งเดียว แล้ว**เงียบ 60 นาที** (ปรับได้ด้วย `-CooldownMinutes`) — ถ้า API มีปัญหาทั้งวัน จะได้แจ้งไม่เกิน 1 ครั้ง/ชั่วโมง ไม่ใช่ทุกนาที

| ข้อความที่ได้รับ | ความหมาย | ควรทำ |
|---|---|---|
| `👀 Fallback Watch` + `1. nemotron → gemini` | โมเดลหลัก (nemotron:free) มีปัญหา → ไปชั้น 1 (gemini) | เช็ค OpenRouter quota (รอ reset เที่ยงคืน หรือเติม $10) |
| `... 2. gemini → gemma` | Gemini ชน quota → ไปชั้น 2 (gemma:free) | เช็ค Gemini quota (รอ ~1 นาที ฟื้นเอง) |
| `... 3. gemma → solar-pro4:free (Nous)` | OpenRouter free quota หมด → ใช้ Nous Portal ฟรี | รอ OpenRouter reset (เที่ยงคืน UTC) หรือเติม $10 → 1,000 req/วัน |
| `... 4. stepfun:free → gemini-3.6-flash (Gemini)` | เรียงไปถึงชั้นสุดท้ายแล้ว | API หลัก+สำรองมีปัญหาพร้อมกัน → รอหรือเติม credits |
| (ไม่มีข้อความ) | bot ยังใช้ nemotron:free อยู่ หรืออยู่ในช่วงเงียบ (เพิ่งแจ้ง < 60 นาที) | ไม่ต้องทำอะไร |

**จัดการ task:**
```powershell
schtasks /query /TN HermesFallbackWatch /V /FO LIST   # เช็คสถานะ
schtasks /delete /TN HermesFallbackWatch /F           # ปิดการแจ้งเตือน
powershell -ExecutionPolicy Bypass -File 'C:\AI Factory\install-fallbackwatch-task.ps1'   # สร้างใหม่
```

**หลักการทำงาน:** จำตำแหน่ง (byte-offset) ใน `logs\agent.log` ที่ตรวจล่าสุดไว้ที่ `state\fallback-watch.offset` → ตรวจส่วนใหม่เท่านั้น → เจอ `Fallback activated: X → Y` จึงแจ้ง (ทุกชั้น) → **cooldown 60 นาที** (`state\fallback-watch.cooldown`) กันแจ้งซ้ำ + dedupe บรรทัด (`state\fallback-watch.last`) กันซ้ำของเหตุการณ์เดิม

> 📌 ครั้งแรกที่ติดตั้ง สคริปต์จะตั้งฉนวน (จำเหตุการณ์เก่า ไม่แจ้ง) — กันสแปม
> 📌 chain ล้มพร้อมกัน 3 ชั้นในวินาทีเดียว = ข้อความเดียว 3 บรรทัด (ไม่สแปม)
> 📌 `-TestSend` ส่งข้อความทดสอบเสมอ (ข้าม cooldown) — ใช้ทดสอบได้ทุกเมื่อ

---

## 📡 การแจ้งเตือนอัตโนมัติ (ถ้า Telegram ส่งข้อความ 🧪 Health Check มา)

Task `HermesHealthCheck` รันทุก 30 นาที → ส่งข้อความมาเฉพาะเมื่อพบปัญหา:

| ข้อความที่ได้รับ | ความหมาย | ควรทำ |
|---|---|---|
| `❌ มีปัญหา! ดู workthrough.md` + รายการ ❌ | ระบบมีจุดเสียหาย | แก้ตามหัวข้อที่ ❌ ชี้ (A-J) |
| `⚠️ ปกติโดยรวม แต่มีข้อควรสังเกต` + รายการ ⚠️ | มีจุดที่ควรดู | ดูรายละเอียด ⚠️ ในข้อความ |
| (ไม่มีข้อความ) | ทุกอย่างปกติ | ไม่ต้องทำอะไร |

**จัดการ task:**
```powershell
schtasks /query /TN HermesHealthCheck /V /FO LIST   # เช็คสถานะ
schtasks /delete /TN HermesHealthCheck /F           # ปิดการแจ้งเตือน
powershell -ExecutionPolicy Bypass -File 'C:\AI Factory\install-healthcheck-task.ps1'   # สร้างใหม่
```

> 📌 task นี้รันเฉพาะตอน **login อยู่** (ค่าเริ่มต้นของ Windows) — ถ้าเครื่องค้างที่หน้า login หลัง reboot การแจ้งเตือนจะหยุดจนกว่าจะ login (แต่ gateway ยัง start ผ่าน AtStartup ตามปกติ)

---

## 🕰️ ประวัติปัญหาที่เคยเจอ (แก้แล้วทั้งสิ้น)

| วันที่ | อาการ | สาเหตุ | วิธีแก้ |
|---|---|---|---|
| 10 ส.ค. 69 | Bot เงียบ 15 นาที | `gw-hidden.ps1` redirect ไป pipe ที่ไม่มีใครอ่าน → pipe เต็ม → thread ค้างใน logging | แก้ launcher redirect ไปไฟล์ `gateway-console.log` + restart |
| 10 ส.ค. 69 | `phi4-mini is not a valid model ID` | fallback entry ใช้ `provider: ollama` (runtime ไม่รู้จัก) → ส่งผิดที่ OpenRouter | เปลี่ยนเป็น `provider: custom` + `base_url` |
| 10 ส.ค. 69 | Gemini 429 quota หมดบ่อย | free tier 20 req/นาที | fallback อัตโนมัติ + (ทางเลือก) เปิด billing |
| 10 ส.ค. 69 | Gateway ติด "Running" แต่ไม่ทำงาน | vbs watcher วน loop เมื่อ pid file หาย | `schtasks /end` + kill wscript + `/run` ใหม่ |
| 10 ส.ค. 69 | Ollama ผูกกับ localhost เท่านั้น (เครื่องบ้านต่อไม่ได้) | OLLAMA_HOST ยังไม่ตั้ง | ตั้ง `OLLAMA_HOST=100.77.88.33:11434` + firewall เฉพาะ Tailscale |
| 10 ส.ค. 69 | auto-start ต้อง login ก่อน | task trigger เป็น AtLogon | เปลี่ยนเป็น **AtStartup** (boot) |
| 10 ส.ค. 69 | bot ตายทั้ง chain ตอน 15:32 ("provider failed after retries") | Gemini 429 → OpenRouter free **หมดโควต้าวัน** (free-models-per-day 50 ครั้ง) → phi4-mini 400 "does not support thinking" | เพิ่ม `reasoning_overrides: {phi4-mini: false}` ใน config.yaml + restart |
| 10 ส.ค. 69 | OpenRouter free หมดโควต้าวันละ 50 ครั้ง | free tier ขีดจำกัดต่อวัน | รอ reset (เที่ยงคืน UTC) หรือเติม $10 credits → ปลดล็อก 1000 free/วัน |
| 10 ส.ค. 69 | อยากรู้เมื่อ bot ตกไปใช้ Ollama | Hermes ไม่มีฟีเจอร์แจ้งเตือน fallback ในตัว | สร้าง `fallback-watch.ps1` + task `HermesFallbackWatch` (ทุก 1 นาที, byte-offset กันแจ้งซ้ำ) |
| 13 ส.ค. 69 | ข้อความแรกช้าเพราะต้องโหลดโมเดล local ใหม่ (โมเดลหลุดจาก memory ได้โดยไม่มีใครรู้) | LM Studio unload โมเดลเมื่อ daemon restart — สคริปต์เดิมเช็คแค่ตอน boot | เพิ่ม **watchdog** `lmstudio-watch.ps1` + task `LMStudioWatch` (ทุก 2 นาที ผ่าน hidden-runner.vbs) — เช็ค daemon+โมเดล+server ถ้าหายกู้คืนทันที + `lmstudio-start.ps1` ตรวจผล load จริง |
| 13 ส.ค. 69 | เปิดใช้ **Nous Portal** (provider ฟรีในตัวของ Hermes) เป็นชั้น fallback ใหม่ | login เว็บบน browser อย่างเดียวไม่พอ ต้อง `hermes portal login` (OAuth device-code) ถึงจะได้ token เข้า auth.json | login สำเร็จ + เทสต์โมเดลฟรี 4 ตัวผ่าน (solar-pro4, step-3.7-flash, hy3, laguna-s-2.1) → เพิ่ม `provider: nous, model: upstage/solar-pro4:free` ใน config.yaml เป็นชั้น 3 (ระหว่าง gemma → qwen3.5-9b) |
| 10 ส.ค. 69 | อยากให้แจ้งทุกชั้น fallback (ไม่ใช่แค่ Ollama) | เดิมจับเฉพาะ phi4-mini | ขยาย `fallback-watch.ps1` จับทุก "Fallback activated" + รวม chain ข้อความเดียว + dedupe หลายบรรทัด |
| 10 ส.ค. 69 | แจ้งเตือนถี่เกินไป (3 ข้อความ/นาที ตอน quota หมด) | แจ้งทุกครั้งที่ fallback เกิด | เปลี่ยนเป็น **cooldown 60 นาที** — แจ้งครั้งเดียวแล้วเงียบ (ปรับด้วย `-CooldownMinutes`) |
| 10 ส.ค. 69 | คำตอบจาก local AI ภาษาไทยเพี้ยน/ตอบมั่ว (ถามประกัน → ตอบสเปครถ) | phi4-mini 3.8B อ่อนภาษาไทย + hallucinate | เปลี่ยน local AI เป็น **qwen3:8b** (5.2GB) — ฉลาดกว่า + ภาษาไทยดีกว่ามาก (config + health-check + fallback-watch + docs อัปเดตให้แล้ว) |
| 13 ส.ค. 69 | เปลี่ยน local AI จาก **Ollama** → **LM Studio** | อยากได้ UI จัดการโมเดล + ควบคุม VRAM ดีกว่า | ติดตั้ง LM Studio + โหลด **qwen3.5-9b Q4_K_M** (5.6GB ฟิต 6GB VRAM, 64K context) — config/base_url เป็น `100.77.88.33:1234` + server bind 0.0.0.0 + autostart ผ่าน `LMStudioServer.lnk` → `lmstudio-start.ps1` (headless) — แล้วลบ Ollama + โมเดล qwen3:8b ทิ้ง |
| 10 ส.ค. 69 | พยายามเพิ่มชั้น **Groq** (`gpt-oss-120b`) เป็น fallback ฟรี | Groq free tier จำกัด **8,000 TPM** แต่ Hermes ส่ง ~17k tokens/request → **413 ทุกครั้ง** | ลบ Groq ออก — ทางออกจริงคือเติม **$10 ครั้งเดียวที่ OpenRouter** ปลดล็อก free models เป็น 1,000 req/วัน (key `GROQ_API_KEY` ยังเก็บไว้ใน .env เผื่ออัปเกรด Dev tier ทีหลัง) |
| 14 ส.ค. 69 | **Bot เงียบทั้งคืน ~6 ชม.** (gateway ตายหลัง reboot ไม่มีใคร restart ให้) | เครื่อง reboot → task `HermesGateway` (AtStartup) เริ่ม gateway → ตายกลางคัน → `RestartCount=3` (ลอง restart แค่ 3 ครั้งใน 1 นาที) หมดแล้ว **เลิกพยายาม** | เพิ่ม **watchdog** `gateway-watch.ps1` + task `HermesGatewayWatch` (ทุก 2 นาที ผ่าน hidden-runner.vbs) — เช็ค heartbeat ถ้าเก่าเกิน 4 นาที → ฆ่า gateway process ที่เหลือ + ล้าง pid/lock + `schtasks /run` เริ่มใหม่ให้อัตโนมัติ (ทดสอบจริง: จำลอง heartbeat ค้าง 30 นาที → restart ให้ภายใน ~1 นาที, pid 3268) |
| 14 ส.ค. 69 | gateway ตายหลัง reboot กลางคืนแล้ว**ต้องรอรอบ 2 นาที**กว่า watchdog จะรื้อ + task `HermesGateway` แก้ไม่ได้ (Access denied — สร้างด้วยสิทธิ์สูงกว่า) | trigger เดิมเป็น Boot+Interactive (ต้อง login ก่อนถึงรัน) + `RestartCount=3` | เพิ่ม task **`HermesGatewayLogonKick`** — trigger `AtLogOn -User suras` (เฉพาะ user ไม่ง้อ admin) รัน `gateway-watch.ps1` **ทันทีที่ login** — ถ้า gateway ตายค้างจากคืนก่อน bot กลับมาทันทีที่เปิดเครื่อง (ทดสอบจริง: fire task → restart ให้ใน ~45 วิ, pid 29424) — รวมกับ `HermesGatewayWatch` (ทุก 2 นาที) = คุ้มกันครบ 2 ชั้น |

---

*เอกสารนี้เป็นส่วนหนึ่งของระบบที่ `C:\AI Factory` — อัปเดตเมื่อเกิดปัญหาใหม่ทุกครั้ง*
