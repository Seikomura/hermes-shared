# 🤖 Hermes AI Factory — ภาพรวมระบบ (System Overview)

> อัปเดตล่าสุด: 16 ส.ค. 2026 — ใช้แชร์ทีม / onboard ผู้ดูแลระบบใหม่
> อ่านเอกสารละเอียด: `README.md` (หลัก) · `Workthrough.md` (แก้ปัญหาครบ + Changelog v1-v11) · `Quick-Start.md` (เริ่มใช้) · `FALLBACK-AI-SETUP.md` (config + คำสั่งเช็ค)

---

## 1. ระบบคืออะไร

Hermes Agent (v0.20.0) — **Telegram bot + agent orchestration** ที่เครื่องบ้าน (Windows) ทำหน้าที่เป็น AI Factory:
- คุยผ่าน **Telegram** (bot ตัวเดียว รองรับงานยาว/งานสั้น)
- รัน **fallback chain 14 ชั้น** — primary = OpenRouter ฟรี (Nemotron 3 Ultra 550B) → ไล่ลงไปถึง LM Studio เครื่องนี้ (ฉุกเฉิน)
- มี **pipeline งาน**: factory_manager (product) · video_builder (วิดีโอรีวิว) · e-book · shopee_research
- **self-heal อัตโนมัติ**: gateway ตาย → bat watchdog restart เอง / proxy ตาย → ฟื้น ≤2 นาที / fallback ตกถึงชั้นสุดท้าย → แจ้งเตือน Telegram

### เครื่อง 2 เครื่อง (แชร์ repo `github.com/Seikomura/hermes-shared`)
| เครื่อง | บทบาท | LM Studio |
|---|---|---|
| **เครื่องบ้าน** (เครื่องนี้, `C:\AI_FACTORY`) | bot หลัก + AI Factory | qwen3-1.7b (32K) — idle-based โหลดเฉพาะเมื่อจำเป็น |
| **เครื่องทำงาน** (office, `msi` @ `100.77.88.33` ผ่าน Tailscale) | local AI สำรอง (ชั้น ⑬) | qwen3.5-9b (64K) — auto-start ตอน login |

---

## 2. Fallback chain 14 ชั้น (`config.yaml`)

```
Primary  nvidia/nemotron-3-ultra-550b-a55b:free        (openrouter)  ← agent orchestration
 1       nvidia/nemotron-3.5-lightning:free            (openrouter)
 2       poolside/laguna-s-2.1:free                     (openrouter)  agentic coding
 3       nvidia/nemotron-3-super-120b-a12b:free        (openrouter)
 4       cohere/north-mini-code:free                    (openrouter)  JSON tool use
 5       openai/gpt-oss-20b:free                        (openrouter)  function calling
 6       nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free (openrouter)  multimodal
 7       google/gemma-4-26b-a4b-it:free                 (openrouter)
 8       upstage/solar-pro4:free                        (nous)  524K ctx
 9       tencent/hy3:free                               (nous)  295B reasoning
10       stepfun/step-3.7-flash:free                    (nous)  multimodal
11       gemini-3.6-flash                               (gemini)  ต้องมี GEMINI_API_KEY
12       qwen/qwen3.5-9b                                (custom → 100.77.88.33:1234)  เครื่องทำงาน
13       qwen/qwen3-1.7b                                (lmstudio → 127.0.0.1:1234)   เครื่องนี้ (CPU-only, ช้า)
```

- **Per-turn:** ทุกข้อความใหม่เริ่มที่ Primary เสมอ → ล้มค่อยไล่ลง
- `custom_providers`: `lmstudio-work` (งาน, 64K) + `lmstudio-local` (เครื่องนี้, 32K)
- `auxiliary.compression` = OpenRouter ฟรี (ใช้บีบ context เมื่อ session ยาว)

---

## 3. สถาปัตยกรรม & การทำงาน

```
Telegram ──(proxy 8899, IPv4)──▶ Hermes Gateway ──▶ fallback chain ──▶ ตอบกลับ
                                    │
                                    ├─▶ skill ai-factory → factory_manager / video_builder / ebook / shopee
                                    ├─▶ sessions (state.db) / kanban / cron
                                    └─▶ heartbeat (state/gateway.heartbeat) ทุก ~60s

Watcher/Tasks (Task Scheduler):
  AI_Factory_Gateway     bat watchdog — spawn gateway + restart เองถ้าตาย (หลัก)
  HermesGatewayWatch     ทุก 2 นาที — ฆ่า gateway ค้าง + self-heal proxy 8899 + รัน lmstudio-alert
  HermesFallbackWatch    ทุก 1 นาที — แจ้งเตือน Telegram เมื่อ fallback activated (cooldown 60 นาที)
  HermesHealthCheck      ทุก 30 นาที — รายงานสุขภาพระบบ → Telegram (มีปัญหาเท่านั้น)
  LMStudioWatch          ทุก 2 นาที — idle-based: เงียบ 30 นาที → unload โมเดล / มี turn → โหลดกลับ
```

### กลไกกัน bot เงียบ (3 ชั้น)
| ชั้น | กลไก | กู้คืนภายใน |
|---|---|---|
| ① | `gateway-watch.ps1` — ฆ่า gateway ค้าง + proxy self-heal ทุก 2 นาที | ≤2 นาที |
| ② | `start_gateway.bat` — `:ensure_proxy` + restart gateway เมื่อ exit | ทันที |
| ③ | `HermesHealthCheck` — เช็คครบ (heartbeat/process/proxy 8899/chain/keys/errors) | ≤30 นาที + แจ้งเตือน |

### ⚠️ กฎสำคัญ (บทเรียน v7 + v11)
- **อย่า** `schtasks /run` watcher ซ้อน bat loop → 2 gateway เขียน heartbeat ไฟล์เดียวกัน → JSON เพี้ยน → restart วน
- **อย่า** อ่าน heartbeat โดยไม่ retry (gateway เขียนแบบไม่ atomic → partial write → ตัดสินใจผิด ฆ่า gateway ที่ปกติ)
- Kill แบบ `taskkill /F` ต้องลบ `gateway.lock` + `kanban/.dispatcher.lock` ค้างด้วย

---

## 4. สคริปต์หลัก (อ้างอิง)

| ไฟล์ | หน้าที่ |
|---|---|
| `shared\tools\start_gateway.bat` | start gateway + watchdog loop + proxy self-heal |
| `shared\hermes_home\gateway-watch.ps1` | ทุก 2 นาที: ฆ่า gateway ค้าง + proxy self-heal + รัน lmstudio-alert |
| `shared\hermes_home\health-check.ps1` | เช็คสุขภาพครบวงจร (exit 0/1/2) |
| `shared\tools\lmstudio-alert.py` | แจ้งเตือน 🐌 เมื่อ turn ตกถึงชั้น lmstudio (⑭) |
| `shared\hermes_home\lmstudio-watch.ps1` | idle-based: unload 30 นาที / โหลดกลับเมื่อมี turn (32K) |
| `shared\hermes_home\fallback-watch.ps1` | แจ้งเตือน fallback activated (cooldown 60 นาที) |
| `shared\tools\model-health-check.py` | ตรวจ availability + latency โมเดล orchestration 8 ตัว |
| `shared\tools\telegram-ipv4-proxy.py` | proxy IPv4 (port 8899) — กัน IPv6 route พังของ ISP |
| `shared\tools\watchdog_notify.py` | แจ้ง Telegram เมื่อ gateway ถูก restart |
| `shared\tools\video_builder.py` | สร้างวิดีโอรีวิว (ffmpeg + edge-tts ฟรี 100%) |
| `shared\tools\check-gateway-running.ps1` | guard กัน double gateway |

### Port
- `8899` — Telegram IPv4 proxy (ต้องฟังเสมอ)
- `1234` — LM Studio (เครื่องนี้ bind 0.0.0.0 / เครื่องทำงานผ่าน Tailscale)

---

## 5. Scheduled Tasks

| Task | ความถี่ | ทำอะไร |
|---|---|---|
| `AI_Factory_Gateway` | at logon + loop | รัน gateway (watchdog) |
| `HermesGatewayWatch` | ทุก 2 นาที | ฆ่า gateway ค้าง + proxy self-heal + lmstudio-alert |
| `HermesFallbackWatch` | ทุก 1 นาที | แจ้งเตือน fallback activated |
| `HermesHealthCheck` | ทุก 30 นาที | รายงานสุขภาพ → Telegram (มีปัญหาเท่านั้น) |
| `LMStudioWatch` | ทุก 2 นาที | idle-based unload/load โมเดล 32K |

---

## 6. ไฟล์สำคัญ & ความปลอดภัย

| ไฟล์ | เนื้อหา | ขึ้น git? |
|---|---|---|
| `shared\hermes_home\config.yaml` | chain 14 ชั้น + custom_providers | ❌ (เฉพาะเครื่อง — path ต่างกัน) |
| `shared\hermes_home\.env` | OpenRouter / Gemini / Telegram keys | ❌ **ห้ามขึ้น git เด็ดขาด** |
| `shared\hermes_home\auth.json` | Nous login | ❌ |
| `config.orchestration.example.yaml` | template ไม่มี secret | ✅ (repo) |
| docs + scripts (repo) | README/Workthrough/Quick-Start/FALLBACK + scripts | ✅ |

- **pre-commit hook** (`check-secrets.ps1`) กัน secret หลุดขึ้น GitHub — push มีผล PASS ทุกครั้ง
- ตรวจซ้ำด้วย `check-secrets.ps1` ได้ทุกเมื่อ

---

## 7. คำสั่งเช็คสถานะ (ย่อ)

```powershell
hermes fallback list                                        # chain ปัจจุบัน
python C:\AI_FACTORY\shared\tools\model-health-check.py    # โมเดล orchestration 8 ตัว
python C:\AI_FACTORY\shared\tools\lmstudio-alert.py --dry-run   # ตรวจ alert (ไม่ส่ง)
powershell -File C:\AI_FACTORY\shared\hermes_home\health-check.ps1 -NotifyTelegram   # สุขภาพเต็ม + ส่งผล
Get-Content C:\AI_FACTORY\shared\hermes_home\logs\agent.log -Tail 50 | Select-String "turn:|API call #1:|Fallback activated"
netstat -ano | findstr ":8899 :1234"                        # proxy + LM Studio
```

### ดูว่า bot ตอบผ่านชั้นไหน (จาก agent.log)
```
conversation turn: ... provider=openrouter      ← ชั้นหลัก
provider=nous / provider=gemini / provider=custom (100.77.88.33) / provider=lmstudio
```
ละเอียด + ตัวอย่างจริง: **Workthrough §10.5** (มีตัวอย่าง 4 ชุด E2E จริง)

---

## 8. สถานะปัจจุบัน (16 ส.ค. 2026)

- ✅ Gateway Connected (Telegram polling) + heartbeat สด + proxy 8899 ฟัง
- ✅ Watcher นิ่ง (v11 fix — ไม่ restart วน) + RAM ~0.7GB free
- ✅ E2E ผ่าน: "สวัสดี" → openrouter (Nemotron 3 Ultra) 98 chars ส่งถึง (23:20)
- ✅ Health-check exit 0 (WARN ที่เหลือ = transient Nvidia error + เครื่องทำงาน offline)
- ⚠️ เครื่องทำงาน `msi` offline 2 วัน — เปิดแล้ว `sync.ps1 -Scripts` + ปรับ config เฉพาะเครื่อง (README)

### Changelog ล่าสุด (Workthrough §14)
- **v11** — แก้ watcher restart วน (2 กลไกชนกัน + retry อ่าน heartbeat)
- **v10** — alert เมื่อ fallback ตกถึงชั้น lmstudio (⑭)
- **v9** — ทดสอบบังคับชั้น lmstudio: เลือกชั้นถูก แต่ CPU-only ช้าเกินจริง
- v8-v1 — idle-based LM Studio / กู้ bot เงียบ (proxy ตาย) / วิดีโอรีวิวแรก / chain 14 ชั้น ฯลฯ
