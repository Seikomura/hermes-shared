# 🤖 Hermes Gateway + AI Fallback System

> ระบบ Bot Telegram ที่ใช้ **Hermes Agent** เป็นสมอง ทำงานเงียบๆ เบื้องหลังเครื่องทำงาน (Windows)
> พร้อมระบบ fallback หลายชั้น: OpenRouter (free) → Gemini API → Local AI (LM Studio)

---

## 📌 ระบบนี้คืออะไร

| ส่วน | บทบาท |
|---|---|
| **Hermes Agent** | ตัว AI agent ที่มี tool-calling (รันคำสั่ง, อ่านไฟล์, ท่องเว็บ ฯลฯ) |
| **Telegram Gateway** | คอยฟังข้อความจาก Telegram bot → ส่งให้ Hermes ประมวลผล → ตอบกลับ |
| **Fallback Chain** | เมื่อโมเดลหลักล่ม/quota หมด จะสลับไปโมเดลสำรองตามลำดับอัตโนมัติ |
| **LM Studio (Local AI)** | โมเดล qwen3.5-9b รันบนเครื่องทำงาน (RTX 4050 6GB) ใช้เป็นชั้นสุดท้าย (ไม่ต้องพึ่งอินเทอร์เน็ตภายนอก) |
| **Tailscale** | VPN ส่วนตัว เชื่อมเครื่องทำงาน ↔ เครื่องบ้าน (เครื่องบ้านใช้ local AI ของเครื่องทำงานได้) |

---

## 🏗️ สถาปัตยกรรม

```
┌─ Telegram (มือถือ/PC) ─────────────────────────────┐
│  ผู้ใช้ส่งข้อความ → Bot                             │
└──────────────────────┬─────────────────────────────┘
                       ▼
┌─ Task Scheduler: HermesGateway (auto-start ตอน boot) ─┐
│  wscript.exe gw-hidden.vbs                             │
│    └─ powershell gw-hidden.ps1                         │
│        └─ cmd /c hermes gateway >> gateway-console.log │
│             (ไม่มี console window, output ไปไฟล์)        │
└──────────────────────┬─────────────────────────────┘
                       ▼
┌─ Hermes Gateway (python, เบื้องหลัง) ────────────────┐
│  ตอบกลับ Telegram + ประมวลผลผ่าน Fallback Chain      │
│  1. nemotron:free      (OpenRouter)         ← หลัก   │
│  2. gemini-3.6-flash   (Google AI Studio)  ← สำรอง 1│
│  3. gemma:free         (OpenRouter)         ← สำรอง 2│
│  4. solar-pro4:free    (Nous Portal)        ← สำรอง 3│
│  5. qwen3.5-9b         (LM Studio ที่เครื่องทำงาน) ← สำรอง 4│
└──────────────────────────────────────────────────────┘
```

**Fallback จะทำงานเมื่อ:** โมเดลหลักเจอ `429 rate limit`, `quota exhausted`, `billing`, หรือ connection/timeout — Hermes จะสลับไปตัวถัดไปอัตโนมัติ (ผู้ใช้ไม่ต้องทำอะไร)

---

## 📂 โฟลเดอร์/ไฟล์สำคัญ

| Path | ความหมาย |
|---|---|
| `C:\AI Factory\` | **HERMES_HOME** — โฟลเดอร์ config + ข้อมูลทั้งหมดของระบบนี้ |
| `C:\AI Factory\config.yaml` | ตั้งค่าโมเดลหลัก + fallback chain + พฤติกรรม agent |
| `C:\AI Factory\.env` | **Key ลับ** (GOOGLE_API_KEY, OPENROUTER_API_KEY, TELEGRAM_BOT_TOKEN) ⚠️ อย่าแชร์ |
| `C:\AI Factory\logs\gateway.log` | log การทำงานของ gateway (รับ/ส่งข้อความ) |
| `C:\AI Factory\logs\agent.log` | log การประมวลผลของ agent (API calls, tools, fallback) |
| `C:\AI Factory\logs\errors.log` | log ข้อผิดพลาดทั้งหมด |
| `C:\AI Factory\gateway-console.log` | console output ของ gateway (redirect จากหน้าต่าง) |
| `C:\AI Factory\state\gateway.heartbeat` | สัญญาณหัวใจ — ใช้เช็คว่า gateway ยัง alive ไหม |
| `C:\AI Factory\gw-hidden.vbs` / `gw-hidden.ps1` | ตัว launch gateway แบบไม่มีหน้าต่าง |
| `C:\AI Factory\gateway.pid` / `gateway.lock` | ไฟล์ระบุ process + ป้องกันรันซ้ำ |
| `C:\Users\suras\AppData\Local\hermes\hermes-agent` | ตัวโปรแกรม Hermes (อย่าแก้เองถ้าไม่จำเป็น) |

---

## 💬 การใช้งาน

### 1) คุยผ่าน Telegram (วิธีปกติ)
ส่งข้อความไปที่ bot ได้เลย — bot จะตอบกลับเอง (โมเดลหลัก nemotron:free)

### 2) ใช้ CLI ตรงๆ (เมื่อ Telegram มีปัญหา หรืออยากเทสต์)
เปิด **PowerShell** แล้วรัน:

```powershell
# ตั้งค่าตัวแปร (รันทุกครั้งที่เปิด PowerShell ใหม่)
$HERMES = 'C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe'
$env:HERMES_HOME = 'C:\AI Factory'

# ถามคำถามครั้งเดียว (จบแล้วจบเลย ไม่ต้องรอ)
& $HERMES chat -q 'สวัสดี ช่วยแนะนำตัวหน่อย' -Q --max-turns 3

# โหมดโต้ตอบ (พิมพ์คุยเรื่อยๆ, พิมพ์ exit เพื่อออก)
& $HERMES chat
```

> ⚠️ เวลารัน CLI ระบบจะใช้ key/โมเดลเดียวกับ bot (อ่าน config เดียวกัน) — **ใช้แก้ปัญหา/เทสต์ได้ทุกอย่างโดยไม่ต้องพึ่ง Telegram**

### 3) คำสั่งเช็คระบบที่ใช้บ่อย

```powershell
& $HERMES status            # สถานะรวม: โมเดล, API keys, .env
& $HERMES fallback list     # ดู fallback chain ปัจจุบัน
& $HERMES logs gateway -n 50    # ดู log gateway 50 บรรทัดล่าสุด
& $HERMES logs errors -n 30     # ดู error ล่าสุด
& $HERMES logs -f               # ตาม log แบบ real-time (Ctrl+C เพื่อออก)
```

---

## 🔄 Fallback Chain (ลำดับสำรอง)

ตรวจสอบได้ด้วย `hermes fallback list` — ควรเห็น:

```
Primary:   nvidia/nemotron-3-super-120b-a12b:free  (via openrouter)
Fallback chain (4 entries):
  1. gemini-3.6-flash  (via gemini)
  2. google/gemma-4-31b-it:free               (via openrouter)
  3. upstage/solar-pro4:free                  (via nous)
  4. qwen/qwen3.5-9b  (via custom)  [http://100.77.88.33:1234/v1]
```

| ชั้น | โมเดล | Provider | ค่าใช้จ่าย | ใช้เมื่อ |
|---|---|---|---|---|
| หลัก | nemotron-3-super-120b:free | OpenRouter | ฟรี | ปกติ |
| สำรอง 1 | gemini-3.6-flash | Google AI Studio | ฟรี (20 req/นาที) | nemotron quota หมด |
| สำรอง 2 | gemma-4-31b-it:free | OpenRouter | ฟรี | Gemini quota หมด |
| สำรอง 3 | solar-pro4:free | Nous Portal | ฟรี (50 RPM) | OpenRouter free quota หมด |
| สำรอง 4 | qwen3.5-9b | LM Studio (เครื่องตัวเอง) | ฟรี 100% | API ภายนอกทั้งหมดล่ม/เน็ตขาด |

> 💡 **Gemini free tier** มี limit **20 request/นาที** (rolling — reset เองใน ~1 นาที)
> เทิร์น agentic ยาวๆ (หลาย tool call) อาจชน quota บ่อย → ระบบจะ fallback เองอัตโนมัติ ไม่ต้องกังวล

---

## 🚀 Auto-start ตอนเปิดเครื่อง

| รายการ | กลไก | เริ่มเมื่อ |
|---|---|---|
| Hermes Gateway (bot) | Task Scheduler: `HermesGateway` (AtStartup) | เปิดเครื่องทันที (ก่อน login) |
| LM Studio (local AI) | Startup folder: `LMStudioServer.lnk` → `lmstudio-start.ps1` | ตอน login |

ลำดับตอนเปิดเครื่อง: `เปิดเครื่อง → HermesGateway เริ่ม (bot พร้อมตอบ) → login → LM Studio เริ่ม headless (local AI พร้อม)`

เช็คสถานะ:
```powershell
schtasks /query /TN HermesGateway /V /FO LIST    # ควรเห็น Schedule Type: At system start up
```

---

### 🛡️ Gateway Watchdog (กัน "bot เงียบ")

Task Scheduler **`HermesGatewayWatch`** รัน `gateway-watch.ps1` **ทุก 2 นาที** (ผ่าน `hidden-runner.vbs` = ไร้หน้าต่าง) — เช็ค `state\gateway.heartbeat` ถ้าเก่าเกิน 4 นาที (gateway ตาย/ค้าง) → **restart ให้อัตโนมัติ**: ฆ่า process เก่า → ล้าง `gateway.pid`/`gateway.lock` → `schtasks /run /TN HermesGateway` เริ่มใหม่

**+ Task `HermesGatewayLogonKick`** (ใหม่) — รัน `gateway-watch.ps1` **ทันทีที่ login** (trigger AtLogOn เฉพาะ user `suras` — ผ่าน `hidden-runner.vbs` ไร้หน้าต่าง): ถ้า boot ครั้งแรกไม่สำเร็จ / gateway ตายค้างจากคืนก่อน → **bot กลับมาทันทีที่เปิดเครื่อง/login** ไม่ต้องรอรอบ 2 นาที

- **ทำไมต้องมี:** task `HermesGateway` เดิมมี `RestartCount=3` (ลอง restart แค่ 3 ครั้งใน 1 นาที แล้วเลิก) + trigger เป็น Boot+Interactive (ต้อง login ก่อนถึงจะรัน) — gateway ตายหลัง reboot กลางคืน → bot เงียบได้หลายชม. จนกว่าจะมีคน restart ด้วยมือ
- **log:** `C:\AI Factory\logs\gateway-watch.log`
- ทดสอบจริงแล้ว: จำลอง heartbeat ค้าง 30 นาที → fire task → restart ให้ภายใน ~1 นาที (heartbeat สด pid ใหม่) — ทั้ง HermesGatewayWatch และ HermesGatewayLogonKick

```powershell
# ตรวจสถานะ task
schtasks /query /TN HermesGatewayWatch /V /FO LIST

# รันเช็คด้วยมือ
powershell -ExecutionPolicy Bypass -File 'C:\AI Factory\gateway-watch.ps1'

# เอา task ออก (ถ้าไม่อยากให้ auto-restart แล้ว)
schtasks /delete /TN HermesGatewayWatch /F
```

---

## ⚙️ การตั้งค่า

### config.yaml (หลัก)
```yaml
model:
  default: nvidia/nemotron-3-super-120b-a12b:free   # โมเดลหลัก
  provider: openrouter
fallback_providers:
  - provider: gemini
    model: gemini-3.6-flash
  - provider: openrouter
    model: google/gemma-4-31b-it:free
  - provider: nous                # Nous Portal (login ผ่าน `hermes portal` — ฟรี)
    model: upstage/solar-pro4:free
  - provider: custom              # ⚠️ ต้องเป็น custom (ไม่ใช่ ollama) + ระบุ base_url
    model: qwen/qwen3.5-9b
    base_url: http://100.77.88.33:1234/v1   # Tailscale IP ของเครื่องทำงาน (LM Studio port 1234)
```

### .env (key ลับ — อย่าแชร์ไฟล์นี้)
```
GOOGLE_API_KEY=...
OPENROUTER_API_KEY=...
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_USERS=...
```

> 🔑 **แก้ .env หรือ config.yaml แล้วต้อง restart gateway** ถึงจะมีผล (ดูวิธีใน `workthrough.md`)

---

## 📡 การแจ้งเตือนอัตโนมัติ (Monitoring)

ระบบตรวจสุขภาพอัตโนมัติ: **Task Scheduler `HermesHealthCheck`** รัน `health-check.ps1` ทุก 30 นาที

- **ส่งข้อความเข้า Telegram เฉพาะเมื่อมีปัญหา** (CRIT = ❌ แจ้งทันที, WARN = ⚠️ แจ้งสั้นๆ)
- ระบบปกติ = **ไม่ส่ง** (ไม่รบกวน)
- ส่งผ่าน **Telegram Bot API ตรงๆ** (อ่าน token จาก .env แบบไม่โชว์ค่า, JSON UTF-8 ภาษาไทยไม่เพี้ยน) — **ทำงานได้แม้ gateway จะพัง**

```powershell
# ทดสอบส่งข้อความ (คุณจะเห็นข้อความทดสอบใน Telegram)
powershell -ExecutionPolicy Bypass -File 'C:\AI Factory\health-check.ps1' -NotifyTelegram -AlwaysReport

# ตรวจสถานะ task
schtasks /query /TN HermesHealthCheck /V /FO LIST

# เอา task ออก (ถ้าไม่อยากให้แจ้งเตือนแล้ว)
schtasks /delete /TN HermesHealthCheck /F
```

> 📌 ถ้าแก้ `health-check.ps1` ต้องระวัง **UTF-8 with BOM** (ไม่งั้น PowerShell 5.1 อ่านภาษาไทยเพี้ยน)

### 👀 แจ้งเตือน fallback ทุกชั้น (Fallback Watch)

Task Scheduler **`HermesFallbackWatch`** รัน `fallback-watch.ps1` ทุก 1 นาที — ตรวจ `logs\agent.log` หาเหตุการณ์ "Fallback activated" **ทุกชั้น** (gemini → gemma → nous → qwen3.5-9b/LM Studio) แล้ว**ส่งข้อความแจ้งเตือนเข้า Telegram ทันที**

- **แจ้งเมื่อ:** bot ต้องสลับไปโมเดลสำรองชั้นไหนก็ได้ (nemotron หลักมีปัญหา = ชั้น 1 Gemini, Gemini หมด = ชั้น 2 gemma, OpenRouter quota หมด = ชั้น 3 Nous, ถึง LM Studio = ชั้น 4)
- **chain ล้มพร้อมกันหลายชั้น → รวมส่งข้อความเดียว** (ไม่สแปม 3 ข้อความรวด)
- **cooldown 60 นาที** — แจ้งครั้งเดียวแล้วเงียบ (ปรับได้ด้วย `-CooldownMinutes`) กันสแปมตอน quota หมดทั้งวัน
- **ใช้ byte-offset จำตำแหน่ง log ที่ตรวจแล้ว** → ตรวจซ้ำไม่แจ้งซ้ำ (ไม่สแปม)
- ครั้งแรกที่ติดตั้งจะตั้งฉนวนอัตโนมัติ (ไม่แจ้งเตือนเหตุการณ์เก่าในประวัติ)
- ส่งผ่าน Bot API ตรงๆ ภาษาไทยไม่เพี้ยน ทำงานได้แม้ gateway พัง

```powershell
# ทดสอบส่งข้อความทดสอบ
powershell -ExecutionPolicy Bypass -File 'C:\AI Factory\fallback-watch.ps1' -TestSend

# ตรวจสถานะ task
schtasks /query /TN HermesFallbackWatch /V /FO LIST

# เอา task ออก (ถ้าไม่อยากให้แจ้งแล้ว)
schtasks /delete /TN HermesFallbackWatch /F
```

---

## ⚠️ ข้อควรรู้

1. **เครื่องทำงานห้ามตั้ง sleep** — เครื่องบ้านใช้ local AI ผ่าน Tailscale ตลอดเวลา ต้องเปิดเครื่องค้างไว้
2. **Tailscale**: ทั้ง 2 เครื่องต้อง login **บัญชีเดียวกัน** ถึงจะเห็นกัน (ถ้าคนละบัญชี = คนละ tailnet = ติดต่อกันไม่ได้)
3. **เครื่องบ้านไม่ต้องลง LM Studio** — แค่ชี้ base_url มาที่เครื่องทำงาน (`100.77.88.33:1234`) — แต่ LM Studio ต้องตั้ง server ให้ bind `0.0.0.0` (ตั้งแล้วใน `lmstudio-start.ps1`)
4. **OpenRouter free models** บางตัวรองรับ tool-calling ไม่ครบ — ถ้า bot ทำงานผิดปกติลอง `hermes fallback list` ดู
5. **Telegram fallback IPs** ถูกตั้งไว้แล้ว (`149.154.166.110`, `149.154.167.220`) — ช่วยได้ถ้า Telegram โดนบล็อก DNS

---

## 🆘 เกิดปัญหา?

เปิด **`workthrough.md`** — คู่มือแก้ปัญหาทีละขั้นตอน (ภาษาไทย) รวมถึงวิธีใช้ CLI ฉุกเฉินเมื่อ Telegram ใช้ไม่ได้
