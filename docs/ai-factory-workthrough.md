# AI FACTORY — คู่มือการใช้งาน (Workthrough)

> อัปเดตล่าสุด: 19 สิงหาคม 2026 (v13 — แก้ bat loop guard: lifecycle.json fast path + ลบ proxy ซ้อน; ระบบนิ่ง)
> เอกสารนี้อธิบายภาพรวม สถาปัตยกรรม และวิธีใช้งานโปรเจกต์ AI FACTORY ทั้งหมด ตั้งแต่วิธีติดตั้ง เริ่มระบบ ไปจนถึงการสร้าง Product ผ่าน CLI และ Telegram Bot

---

## สารบัญ

1. [โปรเจกต์นี้คืออะไร](#1-โปรเจกต์นี้คืออะไร)
2. [สถาปัตยกรรมระบบและสถานะ](#2-สถาปัตยกรรมระบบและสถานะ)
3. [โครงสร้างโฟลเดอร์](#3-โครงสร้างโฟลเดอร์)
4. [สิ่งที่ต้องเตรียมก่อนเริ่ม](#4-สิ่งที่ต้องเตรียมก่อนเริ่ม)
5. [การตั้งค่า (Setup)](#5-การตั้งค่า-setup)
6. [คำสั่งที่ใช้ประจำ](#6-คำสั่งที่ใช้ประจำ)
7. [การใช้งานผ่าน Telegram Bot](#7-การใช้งานผ่าน-telegram-bot)
8. [รายละเอียดแต่ละ Factory](#8-รายละเอียดแต่ละ-factory)
9. [เส้นทางข้อมูลและ Artifact](#9-เส้นทางข้อมูลและ-artifact)
10. [การดู Log และตรวจสอบระบบ](#10-การดู-log-และตรวจสอบระบบ)
11. [สถานะปัจจุบันและแผนพัฒนา](#11-สถานะปัจจุบันและแผนพัฒนา)
12. [ข้อควรระวังด้านความปลอดภัย](#12-ข้อควรระวังด้านความปลอดภัย)
13. [การแก้ปัญหาเบื้องต้น (Troubleshooting)](#13-การแก้ปัญหาเบื้องต้น-troubleshooting)
14. [Changelog](#14-changelog)

---

## 1. โปรเจกต์นี้คืออะไร

**AI FACTORY** คือระบบ "โรงงานผลิตคอนเทนต์" ที่ทำงานบน Windows โดยใช้ **Hermes Agent** (AI assistant จาก Nous Research) ทำหน้าที่เป็น **Factory Manager** คอยสร้างและจัดการ workspace ของสินค้าแต่ละชิ้นอย่างเป็นระบบ

หลักการทำงาน: ผู้ใช้สั่งงาน (ผ่าน Terminal หรือ Telegram) → Hermes เรียก `factory_manager.py` → สร้างโฟลเดอร์ Product แยกส่วน → รัน workflow ตาม **2 เฟส** (build draft ก่อน แล้วค่อย publish หลังผ่านรีวิว)

ปัจจุบันมี **2 โรงงาน**:

| Factory ID | ชื่อ | สายการผลิต |
|---|---|---|
| `shopee_affiliate` | Shopee Affiliate | วิจัยสินค้า → เลือกสินค้า → เขียนสคริปต์ → สร้างภาพ/Asset → ทำวิดีโอ → เขียน Caption → **รีวิว** → โพสต์ YouTube/TikTok/Facebook |
| `ebook` | E-book | วิจัย → ทำโครงเรื่อง → เขียนบท → แก้ไข → ตรวจสอบข้อเท็จจริง → สร้างภาพ/ปก → ทำ EPUB → ทำ PDF → **รีวิว** → เผยแพร่ |

> **สถานะสำคัญ:** วิดีโอโปรโมต / สคริปต์ / เสียงพากย์ **ทำจริงแล้ว (ฟรี 100%** — ffmpeg + edge-tts ที่เครื่อง); ยังเป็น placeholder เฉพาะส่วนที่ต้องต่อ API จริง: ค้นสินค้า Shopee (รอ keys), การโพสต์โซเชียลมีเดีย, EPUB/PDF ดูรายละเอียดใน [หัวข้อ 11](#11-สถานะปัจจุบันและแผนพัฒนา)

---

## 2. สถาปัตยกรรมระบบและสถานะ

```
┌─────────────────────────────────────────────────────────┐
│                     ผู้ใช้ (คุณ)                          │
│     PowerShell Terminal  หรือ  Telegram Bot             │
└──────────────┬──────────────────────────┬───────────────┘
               │                          │
               ▼                          ▼
   ┌────────────────────┐      ┌───────────────────────┐
   │  Hermes Agent      │      │  Hermes Telegram      │
   │  (interactive CLI) │      │  Gateway (long-poll)  │
   └──────────┬─────────┘      └───────────┬───────────┘
              │                            │
              │  อ่าน skill: ai-factory     │  ปุ่มยืนยัน = clarify tool
              ▼                            ▼
   ┌──────────────────────────────────────────────────────┐
   │        shared/tools/factory_manager.py (CLI)         │
   │   list  create  test  build  review  publish         │
   │   status  artifacts                                  │
   └──────────┬───────────────────────┬──────────────────┘
              │                       │
              ▼                       ▼
   ┌─────────────────────┐   ┌──────────────────────────┐
   │  factories/<id>/    │   │  products/<slug>/        │
   │  config/factory.json│   │  (workspace ของสินค้า)    │
   │  workflows/*.json   │   │  metadata/product.json   │
   │  .env (keys)        │   │  + logs/ สำหรับบันทึก     │
   └─────────────────────┘   └──────────────────────────┘
```

**หลักการออกแบบที่สำคัญ:**
- `factory_manager.py` **ไม่มี logic แบบ if/else เฉพาะโรงงาน** — มันอ่านโครงสร้างจาก `factories/<factory-id>/config/factory.json` (stages, phases, publish_platforms) แล้วทำงานตามนั้น → การเพิ่มโรงงานใหม่ทำได้โดยเพิ่มโฟลเดอร์ config + workflow เท่านั้น
- ทุกอย่างที่ผลิต (artifact) ต้องอยู่ภายใน `products/<slug>/` เท่านั้น
- Keys/ความลับทั้งหมดอยู่ในไฟล์ `.env` ซึ่งถูก Git ignore

### 2.1 สถานะของ Product (State machine)

`metadata/product.json` เก็บ `status`, `phase`, `review`, `published`:

```
สร้าง (create)           build                 review approve        publish
CREATED ────────────→ DRAFT_READY ─────────→ APPROVED ──────────→ PUBLISHED
   │        (phase: build)      │              │      (phase: publish,
   │                            │              │       published: [platforms])
   │                            └→ review reject
   │                                REJECTED ──→ (แก้ไขแล้ว) build ใหม่
   └─ ทุกขั้นตอนถ้า error ─→ FAILED (ดู logs/workflow.json)

หมายเหตุ:
- phase: '' → 'build' → 'publish'  (บ่งชี้เฟสปัจจุบัน)
- review.status: pending / approved / rejected  (build ใหม่จะรีเซ็ตเป็น pending)
- published: รายชื่อแพลตฟอร์มที่โพสต์แล้ว (youtube, tiktok, facebook, publishing)
```

**กติกา (Review gate):** `publish` จะทำงานได้ก็ต่อเมื่อ `review.status == approved` **และ** มี draft (phase = build/publish) เท่านั้น — `--force` เป็นทาง bypass (ต้อง user สั่งชัดเจน)

---

## 3. โครงสร้างโฟลเดอร์

```
C:\AI_FACTORY
├── factories\                          # นิยามของโรงงานแต่ละแห่ง
│   ├── shopee_affiliate\
│   │   ├── config\
│   │   │   ├── factory.json            # โครงสร้างโฟลเดอร์ + stages + phases + publish_platforms
│   │   │   └── integrations.example.json
│   │   ├── workflows\
│   │   │   ├── test.json               # workflow ทดสอบพื้นฐาน
│   │   │   ├── build.json              # เฟส build (draft) — stage video เรียก video_builder.py
│   │   │   ├── publish-youtube.json    # เฟส publish แยกตามแพลตฟอร์ม
│   │   │   ├── publish-tiktok.json
│   │   │   └── publish-facebook.json
│   │   ├── .env.example
│   │   └── README.md
│   └── ebook\
│       ├── config\factory.json
│       ├── workflows\
│       │   ├── test.json
│       │   ├── build.json
│       │   └── publish.json            # ebook: publish แบบขั้นเดียว (ไม่มี --platform)
│       ├── .env.example
│       └── README.md
├── products\                           # workspace ของสินค้าแต่ละชิ้น (สร้างโดย CLI)
│   └── <product-slug>\
│       ├── research\ outline\ scripts\ images\ ...  # ตาม factory.json
│       ├── metadata\
│       │   ├── product.json            # ชื่อ, สถานะ, phase, review, published, jobs, artifacts
│       │   └── workflow_manifest.json  # stages + phases + จุดอ้างอิง integration config
│       ├── scripts\                    # สคริปต์เฉพาะสินค้า
│       └── logs\workflow.json          # ผลรันครั้งล่าสุด
├── shared\
│   ├── tools\factory_manager.py        # ตัวจัดการโรงงาน (CLI)
│   ├── tools\script_writer.py          # เขียนสคริปต์โปรโมตจริง (สรรพคุณ/ราคา/โปรโมชัน)
│   ├── tools\shopee_research.py        # ค้นสินค้า Shopee: extra commission + ความนิยมสูง (ต้องมี keys)
│   ├── tools\video_builder.py          # ประกอบวิดีโอ + voiceover (ffmpeg + edge-tts, ฟรี 100%)
│   ├── tools\telegram-ipv4-proxy.py    # local proxy บังคับ IPv4 ไป Telegram (self-heal: probe ก่อน bind)
│   ├── tools\check-gateway-running.ps1 # ตรวจว่ามี hermes gateway process รันอยู่ไหม (guard กัน double)
│   └── hermes_home\                    # บ้านของ Hermes Agent
│       ├── config.yaml                 # ตั้งค่า model + fallback chain (Gemini/Nous/OpenRouter/local)
│       ├── SOUL.md                     # บุคลิก/บทบาทของ Hermes
│       ├── .env                        # GEMINI_API_KEY, OPENROUTER_API_KEY, TELEGRAM_*
│       ├── skills\ai-factory\SKILL.md  # skill สั่งงานผ่าน Hermes (v1.14.0: research/ปุ่มยืนยัน/วิดีโอฟรี)
│       ├── channel_directory.json      # รายชื่อผู้ใช้ Telegram ที่คุยได้
│       ├── gateway_state.json          # สถานะของ Telegram Gateway
│       ├── logs\gateway.log            # log ของ Gateway
│       ├── logs\watchdog.log           # log การ restart อัตโนมัติ (watchdog)
│       ├── logs\telegram-proxy.log     # log ของ IPv4 proxy (CONNECT แต่ละครั้ง)
│       ├── logs\notify.log             # ผลการส่งแจ้งเตือน Telegram (watchdog_notify.py)
│       └── logs\.watchdog_notify_state.json   # สถานะ notify: บรรทัด watchdog.log ที่ส่งแล้ว
├── logs\                               # logs ระดับโปรเจกต์
│   ├── products\products.jsonl         # ประวัติการสร้างสินค้า + review
│   ├── factories\factories.jsonl       # ประวัติการรัน workflow สำเร็จ
│   └── errors\errors.jsonl             # ประวัติ error
└── Workthrough.md                      # เอกสารนี้
```

---

## 4. สิ่งที่ต้องเตรียมก่อนเริ่ม

| รายการ | รายละเอียด |
|---|---|
| **Windows** | ระบบออกแบบมาให้รันบน Windows native |
| **Python** | สำหรับรัน `factory_manager.py` (ใช้ stdlib เท่านั้น ไม่ต้องติดตั้ง package เพิ่ม) |
| **Hermes Agent** | ติดตั้งอยู่ที่ `C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe` |
| **ffmpeg** (ฟรี) | สำหรับประกอบวิดีโอโปรโมต — ติดตั้ง: `winget install Gyan.FFmpeg` (ตรวจ: `ffmpeg -version`) |
| **edge-tts** *(optional, ฟรี)* | voiceover (Microsoft TTS) — ติดตั้ง: `pip install edge-tts` (ต้องมีอินเทอร์เน็ต; ถ้าไม่มีวิดีโอจะไม่มีเสียงพากย์แต่ยังทำงานได้) |
| **OpenRouter API Key** | ใส่ใน `shared\hermes_home\.env` (ตัวหลัก `OPENROUTER_API_KEY`) |
| **Nous Portal (ฟรี)** | Login OAuth ครั้งเดียวด้วย `hermes auth add nous` — ใช้เป็น fallback ชั้น ②③④ (โมเดลฟรี `:free` ใน subscription) |
| **Telegram Bot Token** *(optional)* | ใส่ใน `shared\hermes_home\.env` ถ้าจะใช้ bot |
| **Keys เฉพาะโรงงาน** *(optional)* | ใส่ใน `factories\<id>\.env` เฉพาะที่จำเป็น |

> **Model 12 ระดับ (API เท่านั้น — 17 ส.ค. 2026 ลบ LM Studio ออกหมดแล้ว)** (ดู/แก้ใน `shared\hermes_home\config.yaml` — orchestration-first): ① **OpenRouter ฟรี (primary)** `nvidia/nemotron-3-ultra-550b-a55b:free` (550B, 1M context — จุดเด่น: **agent orchestration**; ใช้ `OPENROUTER_API_KEY`) → ② **OpenRouter ฟรี** `nvidia/nemotron-3.5-lightning:free` (1M context, reasoning — รุ่นใหม่สุด) → ③ **OpenRouter ฟรี** `poolside/laguna-s-2.1:free` (agentic coding, Terminal-Bench 70.2%) → ④ **OpenRouter ฟรี** `nvidia/nemotron-3-super-120b-a12b:free` (MTP, accuracy สูง) → ⑤ **OpenRouter ฟรี** `cohere/north-mini-code:free` (JSON schema tool use) → ⑥ **OpenRouter ฟรี** `openai/gpt-oss-20b:free` (function calling, structured outputs) → ⑦ **OpenRouter ฟรี** `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free` (multimodal ภาพ/วิดีโอ/เสียง) → ⑧ **OpenRouter ฟรี** `google/gemma-4-26b-a4b-it:free` (native function calling) → ⑨ **Nous Portal ฟรี** `upstage/solar-pro4:free` (524K context — เหมาะงานยาว) → ⑩ **Nous Portal ฟรี** `tencent/hy3:free` (295B MoE, 262K, agentic) → ⑪ **Nous Portal ฟรี** `stepfun/step-3.7-flash:free` (multimodal) → ⑫ **Gemini** `gemini-3.6-flash` (ใส่ `GEMINI_API_KEY` ใน `shared\hermes_home\.env`; ยังไม่ใส่ Hermes จะข้ามไปชั้นถัดไปอัตโนมัติ) — ตรวจสอบรายชื่อโมเดลได้ที่ [OpenRouter models](https://openrouter.ai/api/v1/models) / Nous: `inference-api.nousresearch.com/v1/models` ก่อนเปลี่ยน

---

## 5. การตั้งค่า (Setup)

### 5.1 สร้างไฟล์ .env

คัดลอกจากตัวอย่าง แล้วกรอกค่าที่มี:

```powershell
# 1) สำหรับ Hermes (ตัวหลัก)
Copy-Item C:\AI_FACTORY\shared\hermes_home\.env.example C:\AI_FACTORY\shared\hermes_home\.env
# เปิดแก้ไข ใส่ OPENROUTER_API_KEY, GEMINI_API_KEY (ถ้ามี), TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS

# 2) สำหรับแต่ละโรงงาน (เฉพาะที่จำเป็น)
Copy-Item C:\AI_FACTORY\factories\shopee_affiliate\.env.example C:\AI_FACTORY\factories\shopee_affiliate\.env
Copy-Item C:\AI_FACTORY\factories\ebook\.env.example C:\AI_FACTORY\factories\ebook\.env
```

### 5.2 ตั้งค่า environment variables (ทุกครั้งที่เปิด PowerShell ใหม่)

```powershell
$env:HERMES_HOME='C:\AI_FACTORY\shared\hermes_home'
$env:AI_FACTORY_ROOT='C:\AI_FACTORY'
$hermes='C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe'
```

อธิบาย:
- `HERMES_HOME` → บอก Hermes ว่า config, keys, skills, logs อยู่ที่ไหน
- `AI_FACTORY_ROOT` → ระบุ workspace ของโรงงาน
- `$hermes` → ตัวแปรย่อของ path executable (ต้องตั้งใหม่ทุกหน้าต่าง PowerShell)

> 💡 แนะนำ: ถ้าขี้เกียจพิมพ์ซ้ำ เก็บ 3 บรรทัดนี้ไว้ใน PowerShell Profile หรือไฟล์ `.ps1` แล้ว `.` source ตอนเปิด

### 5.3 ตั้งค่า Gemini API (เมื่อได้ key แล้ว) — fallback ระดับ ⑫

`config.yaml` ตั้งเป็น **12 ระดับ (API เท่านั้น — ลบ LM Studio แล้ว 17 ส.ค. 2026)** ไว้แล้ว (OpenRouter `nemotron-3-ultra-550b-a55b:free` (primary, orchestration) → `nemotron-3.5-lightning:free` → `laguna-s-2.1:free` → `nemotron-3-super-120b-a12b:free` → `north-mini-code:free` → `gpt-oss-20b:free` → `nano-omni-30b-a3b-reasoning:free` → `gemma-4-26b-a4b-it:free` → Nous Portal ฟรี × 3 → `gemini-3.6-flash`) — เพิ่ม key `GEMINI_API_KEY` เพื่อเปิดใช้งานชั้น Gemini (⑫):

1. เปิดไฟล์ `C:\AI_FACTORY\shared\hermes_home\.env` แล้วเพิ่มบรรทัด (key จาก https://aistudio.google.com/apikey):
   ```
   GEMINI_API_KEY=AIza...
   ```
2. บันทึก แล้ว**รีสตาร์ท Hermes / Gateway** (เพื่อโหลด .env ใหม่)

**วิธีเช็คว่า Hermes ใช้ primary (OpenRouter) จริงไหม:**

- **วิธี A (แม่นสุด):** เปิด `& $hermes` แล้วดูบรรทัดแรกตอนเริ่ม session:
  - `🤖 AI Agent initialized with model: nvidia/nemotron-3-ultra-550b-a55b:free` → ✅ ใช้ primary (OpenRouter)
  - `🔄 Fallback model: <model> (<provider>)` → กำลังใช้ตัวสำรอง (ดู troubleshooting ข้อ 13)
- **วิธี B:** พิมพ์ `/status` ใน session → บรรทัด `Model: nvidia/nemotron-3-ultra-550b-a55b:free (openrouter)` → ✅ primary (ถ้าขึ้น provider อื่น = กำลังใช้ fallback)

**ถ้า `gemini-3.6-flash` ใช้ไม่ได้ (error 404 / model not found):**

- แก้ `shared\hermes_home\config.yaml` เปลี่ยน `default` เป็นตัวอื่นที่มีในโค้ด Hermes: `gemini-2.5-flash` / `gemini-3-flash` / `gemini-3.1-flash-lite-preview`
- หรือรันตัวช่วยเลือกแบบโต้ตอบ (เขียน config ให้อัตโนมัติ): `& $hermes model`
- ไม่ต้องแก้ก็ได้ — Hermes จะข้ามไปใช้ fallback ฟรี (Nous Portal → OpenRouter) อัตโนมัติ (ไม่พัง)

> **ยังไม่ใส่ `GEMINI_API_KEY` (ช่วงก่อนได้ key):**
> - เปิด Hermes โหมดคุยปกติครั้งแรก จะขึ้นข้อความ `⚕ No inference provider is configured yet` + ถาม `Set up a provider now? [Y/n]` — **พิมพ์ `n` ข้ามไปได้** ระบบยังทำงานปกติผ่าน OpenRouter ฟรี (ตรวจแล้ว: `hermes chat` ตอบได้จริงผ่าน fallback) พอใส่ key แล้วข้อความนี้จะไม่ขึ้นอีก (ตอนนี้มี `OPENROUTER_API_KEY` แล้ว — ไม่ควรเจอข้อความนี้)
> - คำสั่ง `-z/--oneshot` (script/pipeline) **ไม่ผ่าน fallback chain** — ใช้ primary โดยตรง (ตอนนี้ = OpenRouter lightning ต้องมี `OPENROUTER_API_KEY` ใน .env); ถ้าจะบังคับตัวอื่น: `& $hermes -z "<prompt>" --provider openrouter -m "nvidia/nemotron-3-ultra-550b-a55b:free"`
> - โมเดล `:free` บน OpenRouter อาจเจอ `HTTP 402 ... can only afford N tokens` (ฟรีเครดิตจำกัดต่อ request) — คำตอบหลักยังได้ แต่ขั้นเสริมอย่าง title generation อาจล้มได้ ไม่ใช่ความผิด config

---

## 6. คำสั่งที่ใช้ประจำ

> ใช้สัญลักษณ์ `...` = `python C:\AI_FACTORY\shared\tools\factory_manager.py` เพื่อความกระชับ

### 6.1 เริ่ม Hermes (โหมดคุยใน Terminal)

```powershell
& $hermes
```

- เปิด session แบบคุยโต้ตอบ ใช้ `/exit` หรือ Ctrl+C เพื่อออก
- **ต้องรีสตาร์ท Hermes ทุกครั้ง** หลังแก้ skill หรือ config เพื่อให้โหลดการเปลี่ยนแปลง

### 6.2 เริ่ม Telegram Gateway

**วิธี A — อัตโนมัติตอนเข้าสู่ระบบ (แนะนำ ✅ ตั้งไว้แล้ว):**

Task Scheduler ลงทะเบียนทาสก์ `AI_Factory_Gateway` ไว้แล้ว → **ทุกครั้งที่ login Windows, Gateway จะรันอัตโนมัติ** แบบหน้าต่างเงียบ (ผ่าน `wscript.exe` → `shared\tools\start_gateway_hidden.vbs` → `start_gateway.bat`):

```powershell
schtasks /Query /TN "AI_Factory_Gateway" /V /FO LIST   # ตรวจว่าทาสก์ติดตั้งอยู่
schtasks /Run   /TN "AI_Factory_Gateway"               # รันทาสก์ทันที (ไม่ต้องรอ login)
shared\tools\stop_gateway.bat                          # หยุด Gateway แบบสะอาด (ดูด้านล่าง)
schtasks /Delete /TN "AI_Factory_Gateway" /F           # (ถ้าต้องการ) ลบทาสก์
```

- ไฟล์ที่เกี่ยวข้อง: `shared\tools\start_gateway.bat` (ตั้ง env + รัน `hermes gateway` + **guard กันรันซ้ำ** เช็ค PID ใน `state\gateway.lifecycle.json` + **watchdog**: ถ้า Gateway ตาย/โดนฆ่า จะรอ ~10 วิ แล้วรันใหม่เอง + เช็ค stop marker), `shared\tools\start_gateway_hidden.vbs` (ซ่อนหน้าต่าง + **รอ** bat ทำงาน แล้วส่งต่อ exit code), `shared\tools\register_gateway_task.ps1` (สคริปต์ลงทะเบียนทาสก์), `shared\tools\stop_gateway.bat` (หยุด Gateway แบบสะอาด), `shared\tools\watchdog_notify.py` (แจ้งเตือน Telegram เมื่อ Gateway restart)
- **Auto-restart มี 2 ชั้น:** ① **watchdog ใน bat (หลัก)** — Gateway ตาย/ถูกฆ่าเมื่อไหร่ รีรันเอง (~30 วิ กลับมา `connected`; **ทดสอบแล้ว**) + บันทึกทุก restart ลง `logs\watchdog.log` + **กัน crash loop**: ถ้า Gateway ตายภายใน 60 วิหลังสตาร์ทซ้ำกัน 6 ครั้งติด (เช่น config พัง) จะหยุดรอ (exit 1) ให้ user ดู log แก้ไข ② **Task Scheduler restart-on-failure (สำรอง)** — 3 ครั้ง ห่างกัน 1 นาที ใช้เมื่อ watchdog ตัวมันเองถูกฆ่า — ⚠️ หมายเหตุ: restart-on-failure ของ Task Scheduler **ใช้ไม่ได้กับการรันแบบ manual** (`schtasks /Run` — ทดสอบแล้ว: ทาสก์บันทึก failure (Last Result 1) แต่ไม่ restart) ใช้ได้เฉพาะตอน login trigger เริ่มทาสก์เอง; เพราะฉะนั้น watchdog จึงเป็นกลไกหลักที่การันตีการกู้คืน
- **แจ้งเตือน Telegram เมื่อ Gateway restart:** ทุกครั้งที่ watchdog เขียน log restart → `watchdog_notify.py` ส่งข้อความ ⚠️ ไปยัง `TELEGRAM_ALLOWED_USERS` (อ่าน `logs\watchdog.log` + ส่งเฉพาะบรรทัดใหม่ ผ่านสถานะ `logs\.watchdog_notify_state.json`; ผลการส่งอยู่ที่ `logs\notify.log`; ข้ามบรรทัด "stop requested" อัตโนมัติ) — **ทดสอบแล้ว**: ฆ่า Gateway แล้วได้รับแจ้งเตือนจริง; ถ้า crash loop ครบ 6 ครั้ง จะได้แจ้งเตือน "giving up" ด้วย
- **หยุด Gateway แบบสะอาด:** ⚠️ `schtasks /End` อย่างเดียว **ไม่พอ** (watchdog จะ restart กลับมาเอง) → ใช้ `shared\tools\stop_gateway.bat` (เขียน stop marker + ฆ่า process + /End) — ทดสอบแล้ว: หยุดแล้วอยู่หยุดจริง (ไม่กลับมาเอง) และเริ่มใหม่ได้ด้วย `schtasks /Run`
- ตรวจว่า Gateway รันอยู่: `gateway_state.json` ขึ้น `running` + `telegram.connected` (ดูหัวข้อ 10.2)

**วิธี B — รันแบบ foreground (manual):**

```powershell
& $hermes gateway
```

- เปิด Telegram long-polling แบบ foreground **ต้องเปิดหน้าต่างนี้ค้างไว้** ตลอดการใช้งาน bot
- ถ้าต่อสำเร็จ จะเห็นข้อความ `telegram connected` และ `Gateway running with 1 platform(s)` ใน `shared\hermes_home\logs\gateway.log`
- หยุดด้วย Ctrl+C

### 6.3 ดูรายชื่อ Factory ที่ลงทะเบียน

```powershell
... list
```

แสดง Factory ID, โครงสร้างโฟลเดอร์, stages, phases และ publish_platforms

### 6.4 สร้าง Product workspace

```powershell
... create --factory shopee_affiliate --name "My Product"
```

- สร้างโฟลเดอร์ Windows-safe ใต้ `C:\AI_FACTORY\products\` (อักขระพิเศษ/ช่องว่าง เปลี่ยนเป็น `-`)
- สร้างครบทุกโฟลเดอร์ตาม `factory.json` + `metadata/product.json` (สถานะ `CREATED`, review `pending`) + `metadata/workflow_manifest.json` + `scripts/`
- สร้างหนังสือใช้ `--factory ebook`
- ผลลัพธ์ JSON มี `slug` (ชื่อโฟลเดอร์) และ `status: CREATED`

### 6.5 รัน test workflow (ทดสอบพื้นฐาน)

```powershell
... test --factory shopee_affiliate --product "My-Product"
... test --factory ebook --product "Failure-Test" --fail   # ตัวเลือก --fail: ทำให้ stage แรกพังตั้งใจ
```

- เขียนไฟล์ placeholder ตาม workflow test เท่านั้น ไม่เรียก API จริง
- สำเร็จ → `status: READY` / ล้มเหลว → `status: FAILED` (ตรวจสอบ `products\<slug>\logs\workflow.json`)

### 6.6 เฟส build (สร้าง draft)

```powershell
... build --factory shopee_affiliate --product "My-Product"
```

- รัน workflow เฟส build (research → selection → script → assets → video → captions / หนังสือ: research → ... → pdf)
- สำเร็จ → `status: DRAFT_READY`, `phase: build`, **รีเซ็ต review เป็น pending อัตโนมัติ**
- stage `script`/`video` **ทำของจริงแล้ว** (สคริปต์โปรโมต + วิดีโอ ffmpeg พร้อมเสียงพากย์จากสคริปต์); stage อื่น (research/selection/assets/captions ฯลฯ) ยังเป็น placeholder จนกว่าจะต่อ API จริง

### 6.7 รีวิว (Review gate)

```powershell
... review --product "My-Product" --status approve [--notes "..."]
... review --product "My-Product" --status reject [--notes "..."]
```

- `approve` → `status: APPROVED` (ทำได้เฉพาะเมื่อ draft พร้อม: DRAFT_READY/REJECTED — สินค้าที่ยังไม่ build อนุมัติไม่ได้)
- `reject` → `status: REJECTED` บันทึก `notes` ไว้ แล้ว user แก้ไข → build ใหม่

### 6.8 เฟส publish (โพสต์) — แยกตามแพลตฟอร์ม

```powershell
... publish --factory shopee_affiliate --product "My-Product" --platform youtube   # โพสต์แค่ YouTube
... publish --factory shopee_affiliate --product "My-Product"                     # โพสต์แพลตฟอร์มที่ยังไม่ได้โพสต์ทั้งหมด
... publish --factory ebook --product "My-Book"                                   # ebook: ขั้นเดียว (ไม่มี --platform)
```

- **Gate:** ต้อง `review.status == approved` + มี draft ก่อน ไม่งั้นปฏิเสธ (`ok: false`)
- โพสต์ซ้ำแพลตฟอร์มเดิม / แพลตฟอร์มไม่รู้จัก / โพสต์ครบแล้ว → ปฏิเสธพร้อมข้อความเหตุผล
- สำเร็จ → `status: PUBLISHED`, `phase: publish`, เพิ่มแพลตฟอร์มใน `published[]`, ผลแต่ละแพลตฟอร์มอยู่ใน `platforms_run`
- `--force` = bypass ทุก gate (ต้องใช้อย่างระมัดระวัง)
- **หมายเหตุ:** ผลลัพธ์ตอนนี้ยังเป็น placeholder จริงๆ (ยังไม่โพสต์ขึ้นแพลตฟอร์มจริง)

### 6.9 ตรวจสอบสถานะและไฟล์

```powershell
... status --product "My-Product"       # status, phase, review, published, last_job
... artifacts --product "My-Product"    # รายการไฟล์ที่ gen แล้ว (ไม่รวม metadata/logs)
```

ใช้ `artifacts` ก่อนรีวิว/โพสต์ เพื่อเช็คว่าไฟล์ครบ

---

## 7. การใช้งานผ่าน Telegram Bot

### 7.1 เงื่อนไขก่อนใช้

1. ตั้งค่า `TELEGRAM_BOT_TOKEN` และ `TELEGRAM_ALLOWED_USERS` ใน `shared\hermes_home\.env`
2. เปิด Gateway ค้างไว้ (หัวข้อ 6.2) รอจน log ขึ้น `telegram connected`
3. คุยกับ bot ผ่าน **private message** จาก user ID ที่อนุญาต (ดู `shared\hermes_home\channel_directory.json` — ปัจจุบันมี user ชื่อ "Yoseph" ID `1709297704`)
4. **รีสตาร์ท Hermes** หลังแก้ skill เพื่อโหลด ai-factory v1.14.0

### 7.2 ปุ่มยืนยัน (inline keyboard)

Hermes มี **`clarify` tool** ในตัว (อยู่ใน default toolset) — เมื่อ agent เรียกด้วย `choices` บน Telegram จะ render เป็น **ปุ่มกดได้** อัตโนมัติ (หนึ่งปุ่มต่อ choice + ปุ่ม "✏️ Other" อัตโนมัติ):

```
❓ รีวิว draft ของ 'หูฟังบลูทูธ' — อนุมัติให้โพสต์ได้เลยไหม?

1. อนุมัติ (approve)
2. ส่งกลับแก้ไข (reject)

[ 1 ]          ← ปุ่ม
[ 2 ]          ← ปุ่ม
[ ✏️ Other (type answer) ]
```

- ตัวเลือกต้องอยู่ใน `choices` ของ clarify เท่านั้น (สูงสุด 4 ตัว) — อย่า enumerate ในข้อความคำถาม
- หลัง build เสร็จ bot จะถามรีวิวด้วยปุ่ม approve/reject / หลัง approve แล้ว bot จะถามยืนยันโพสต์ด้วยปุ่ม "ยืนยันโพสต์"/"ไม่เอา" ทุกแพลตฟอร์ม
- **ปุ่มเลือกสินค้า research (แบ่งหน้า):** clarify tool จำกัด `MAX_CHOICES = 4` (ยืนยันในโค้ด `tools/clarify_tool.py`) → แต่ละหน้า = **ปุ่มสินค้า 3 อัน + ปุ่ม `[ ดูอันดับถัดไป ]`** — กดปุ่มถัดไปเพื่อเลื่อนดูจนครบ shortlist (ทุกอันดับเลือกด้วยปุ่มได้); ปุ่ม "✏️ Other" ยังพิมพ์หมายเลข/ชื่อได้ตลอด (เช่น กลับไปอันดับหน้าเก่า)
- **ปุ่มยืนยันก่อนสร้าง Product:** หลังเลือกสินค้าแล้ว bot จะสรุปข้อมูลสินค้าให้ดู พร้อม**แปะลิงก์รูปสินค้า** (field `image_url` จาก `logs\shopee\last_search.json` — Telegram แสดงพรีวิวรูปให้อัตโนมัติ; ถ้าไม่มีรูปจะข้าม) แล้วถามยืนยันด้วยปุ่ม `[ ยืนยัน ] [ เลือกใหม่ ] [ ค้นใหม่ ]` — "เลือกใหม่" = ไม่สร้าง Product (โชว์ shortlist ใหม่ให้เลือก), "ค้นใหม่" = ไม่สร้าง Product แล้วโชว์ **keyword ล่าสุด 3 อันเป็นปุ่ม** (อ่านจาก `logs\shopee\research.jsonl`; กดปุ่มหรือใช้ "✏️ Other" พิมพ์ keyword ใหม่) แล้ว search ใหม่

### 7.3 ค้นสินค้า Shopee ก่อนสร้าง Product (research)

```
คุณ:   /ai-factory หาสินค้า Shopee คอมมิชชันดี ขายดี หน่อย
bot:   ค้นหา: keyword + เกณฑ์สมดุล (คอมมิชชัน ≥15% + ยอดขาย ≥500 + เรียงตามคอมมิชชัน + รวม AMS)
       ผลลัพธ์ (10 อันดับ):
       1. หูฟังบลูทูธ XYZ — 299฿, ขาย 1.2 หมื่น, คอมฯ 25% (+พิเศษ 5%)
       2. ลำโพงพกพา ABC — 450฿, ขาย 8 พัน, คอมฯ 22%
       3. แก้วเก็บความเย็น DEF — 120฿, ขาย 2.5 หมื่น, คอมฯ 20%
       ... (ดูทั้งหมดจากปุ่ม [ ดูอันดับ ] ด้านล่าง)
       ❓ เลือกสินค้าที่จะสร้าง Product ครับ? (หน้า 1/4)
       [ #1 หูฟังบลูทูธ XYZ ]  [ #2 ลำโพงพกพา ABC ]
       [ #3 แก้วเก็บความเย็น DEF ]  [ ดูอันดับ 4-6 ]
       [ ✏️ Other (พิมพ์หมายเลขหรือชื่อสินค้า) ]
คุณ:   กด [ ดูอันดับ 4-6 ]
bot:   ❓ เลือกสินค้าที่จะสร้าง Product ครับ? (หน้า 2/4)
       [ #4 … ]  [ #5 … ]  [ #6 … ]  [ ดูอันดับ 7-9 ]
       [ ✏️ Other (พิมพ์หมายเลขหรือชื่อสินค้า) ]
คุณ:   กด [ #5 … ]
bot:   🖼️ https://down-th.img.susercontent.com/file/yyyyy.jpg   ← แปะลิงก์รูปสินค้า (Telegram แสดงพรีวิว)
       ✅ สินค้าที่เลือก: (สินค้าอันดับ #5) — ราคา/ยอดขาย/คอมมิชชัน ตามผลค้นหา
       ❓ ยืนยันใช้สินค้านี้สร้าง Product ใช่ไหม?
       [ ยืนยัน ]  [ เลือกใหม่ ]  [ ค้นใหม่ ]
คุณ:   กด [ ยืนยัน ]
bot:   สร้าง Product จากสินค้าที่เลือก → export ข้อมูลสินค้าจริง (ราคา/ยอดขาย/คอมมิชชัน)
       → เริ่ม build ได้เลยไหม?

กด [ เลือกใหม่ ] → bot โชว์ shortlist ใหม่แล้วถามเลือกอีกครั้ง (ไม่สร้าง Product)
กด [ ค้นใหม่ ]   → bot โชว์ keyword ล่าสุดเป็นปุ่ม: `[ หูฟังบลูทูธ ] [ ลำโพงพกพา ] [ แก้วเก็บความเย็น ]`
       + ปุ่ม "✏️ Other" สำหรับพิมพ์ keyword ใหม่ → กดปุ่ม/พิมพ์แล้ว search ใหม่ (ไม่สร้าง Product)
```

> ⚠️ ต้องมี Shopee Affiliate API keys + whitelist access ก่อน (ดูหัวข้อ 8.1) — ถ้ายังไม่มี bot จะแจ้งวิธีตั้งค่า ไม่ใช่เดาข้อมูลขึ้นเอง

#### 7.3.1 ตัวอย่างคำสั่ง + ผลลัพธ์จำลอง (ตอนยังไม่มี keys)

**คำสั่ง `search` (ต้องมี keys ก่อน)**

```powershell
python C:\AI_FACTORY\shared\tools\shopee_research.py search --query "หูฟังบลูทูธ" --limit 3
```

- ถ้ายังไม่มี keys → จะเจอ error แบบนี้ (ระบบไม่เดาข้อมูลขึ้นเอง):

```
Missing Shopee Affiliate API credentials.
Register an approved Shopee Affiliate account, request whitelist
access for the Affiliate Open API, then fill in:
  factories/shopee_affiliate/.env
    SHOPEE_AFFILIATE_API_BASE_URL, SHOPEE_AFFILIATE_APP_ID,
    SHOPEE_AFFILIATE_APP_SECRET  (or SHOPEE_AFFILIATE_PARTNER_KEY)
```

- ใส่ keys แล้ว → ผลลัพธ์ประมาณนี้ (**ผลลัพธ์จำลอง** เพื่อให้เห็นฟอร์แมตที่จะได้):

```json
{
  "ok": true,
  "query": "หูฟังบลูทูธ",
  "count": 3,
  "criteria": { "min_commission": 0.15, "min_sold": 500 },
  "items": [
    {
      "index": 1,
      "name": "หูฟังบลูทูธ XYZ รุ่นใหม่ กันน้ำ",
      "price_min": 299.0,
      "price_max": 329.0,
      "sales": 12000,
      "rating": 4.8,
      "commission_rate": 0.25,
      "seller_commission_rate": 0.05,
      "shopee_commission_rate": 0.20,
      "link": "https://shopee.co.th/product/123456",
      "image_url": "https://down-th.img.susercontent.com/file/th-11134207-7r98o-111111"
    },
    {
      "index": 2,
      "name": "หูฟังบลูทูธ ABC ครอบหู",
      "price_min": 450.0,
      "price_max": 499.0,
      "sales": 8200,
      "rating": 4.7,
      "commission_rate": 0.22,
      "seller_commission_rate": 0.0,
      "shopee_commission_rate": 0.22,
      "link": "https://shopee.co.th/product/654321",
      "image_url": "https://down-th.img.susercontent.com/file/th-11134207-7r98o-222222"
    },
    {
      "index": 3,
      "name": "หูฟังบลูทูธ ไร้สาย สเตอริโอ",
      "price_min": 189.0,
      "price_max": 219.0,
      "sales": 31000,
      "rating": 4.6,
      "commission_rate": 0.18,
      "seller_commission_rate": 0.04,
      "shopee_commission_rate": 0.14,
      "link": "https://shopee.co.th/product/987654",
      "image_url": "https://down-th.img.susercontent.com/file/th-11134207-7r98o-333333"
    }
  ]
}
```

> field `image_url` = รูปสินค้า — ใช้แปะพรีวิวตอนยืนยันเลือก (หัวข้อ 7.2) และ**ดาวน์โหลดอัตโนมัติ** ลง `images\img1.<ext>` ตอน export (ดูด้านล่าง)

**คำสั่ง `export` (เลือกสินค้าจาก shortlist ไปสร้าง Product)**

```powershell
python C:\AI_FACTORY\shared\tools\shopee_research.py export --product "หูฟังบลูทูธ" --index 1
```

→ เขียนไฟล์ `products\หูฟังบลูทูธ\source_data\selection.txt`:

```
สินค้า: หูฟังบลูทูธ XYZ รุ่นใหม่ กันน้ำ
ราคา: 299 - 329 บาท
ยอดขาย: 12000 ชิ้น
คอมมิชชันรวม: 25.0%
คอมมิชชันพิเศษ (ร้าน): 5.0%
ลิงก์สินค้า: https://shopee.co.th/product/123456
รูปสินค้า: https://down-th.img.susercontent.com/file/xxxxx.jpg
```

→ **ดาวน์โหลดภาพสินค้าอัตโนมัติ** ลง `products\หูฟังบลูทูธ\images\img1.jpg` (จาก field `image_url` — ไม่สำเร็จจะข้าม แล้ววิดีโอใช้ title card แทน) → จากนั้นรัน `build` ปกติ: stage `script` (`script_writer.py`) จะดึงข้อมูลจริงนี้ไปเขียน `scripts/script.txt` → voiceover พากย์ "...ราคา 299 - 329 บาท..." ในวิดีโอ และวิดีโอใช้**ภาพสินค้าจริง**จาก `images\` (แทนที่จะเป็น title card)

**คำสั่ง `recent` (keyword ล่าสุดที่ค้น — ใช้ทำปุ่ม "ค้นใหม่")**

```powershell
python C:\AI_FACTORY\shared\tools\shopee_research.py recent --limit 3
```

→ อ่านจาก `logs\shopee\research.jsonl` (บันทึกทุกครั้งที่ search):

```json
{
  "ok": true,
  "limit": 3,
  "recent": ["หูฟังบลูทูธ", "ลำโพงพกพา", "แก้วเก็บความเย็น"]
}
```

ยังไม่เคย search → `"recent": []` (bot จะถามพิมพ์ keyword ใหม่แทน)

> 💡 **ทดสอบโฟลว์ล่วงหน้าได้เลยโดยไม่ต้องรอ keys:** สร้าง Product แล้ววางไฟล์ `source_data\selection.txt` เอง (ฟอร์แมตตามด้านบน) + วางภาพสินค้าลง `images\` → รัน `build` ได้ทันที สคริปต์/เสียงพากย์/วิดีโอจะใช้ข้อมูลที่วางไว้ ระบบจะข้ามไฟล์ placeholder (ขึ้นต้นด้วย `Factory=`) อัตโนมัติ และ placeholder stage จะไม่เขียนทับข้อมูลจริง

### 7.4 ตัวอย่างวงจรเต็ม

```
คุณ:   /ai-factory สร้าง Product Shopee ชื่อ หูฟังบลูทูธ
bot:   สร้าง workspace สำเร็จ → products\หูฟังบลูทูธ\ (status: CREATED)

คุณ:   gen draft หูฟังบลูทูธ
bot:   build เสร็จ → DRAFT_READY
       ❓ รีวิว draft ของ 'หูฟังบลูทูธ' — อนุมัติให้โพสต์ได้เลยไหม?
       [ อนุมัติ (approve) ] [ ส่งกลับแก้ไข (reject) ]

คุณ:   กด [ อนุมัติ (approve) ]
bot:   APPROVED
       ❓ ยืนยันโพสต์ไปยัง youtube สำหรับ 'หูฟังบลูทูธ' ใช่ไหม?
       [ ยืนยันโพสต์ ] [ ไม่เอา ]

คุณ:   กด [ ยืนยันโพสต์ ]
bot:   publish youtube สำเร็จ → published: [youtube] (ถ้ายังมี tiktok/facebook ค้าง จะถามต่อทีละตัว)

ถ้ากด [ ส่งกลับแก้ไข (reject) ]:
bot:   ❓ มีอะไรให้แก้ไขใน draft นี้บ้าง?   ← open-ended (ไม่มีปุ่ม)
คุณ:   พิมพ์คำแนะนำ → bot บันทึก notes + REJECTED → แก้แล้วสั่ง build ใหม่
```

### 7.5 กติกาที่ Hermes ปฏิบัติใน Telegram

- สร้าง workspace จริงเสมอ ไม่ตอบรายชื่อสินค้าแทน
- ไม่กล่าวอ้างว่า Product ถูกสร้าง/ถูกโพสต์ ถ้า command ไม่สำเร็จจริง (ต้องดู JSON `PUBLISHED`)
- ไม่สร้าง URL/ราคา/ยอดสต็อก/ลิงก์ affiliate/ผลการโพสต์ขึ้นเอง
- ไม่เขียน artifact นอก `products\<slug>\`
- ไม่ publish โดยไม่ได้รับยืนยันผ่านปุ่มก่อน

---

## 8. รายละเอียดแต่ละ Factory

### 8.1 Shopee Affiliate (`shopee_affiliate`)

**สายการผลิต (stages):**
```
research → selection → script → assets → video → captions → social_posts → publishing
```

**เฟส (phases):**
| เฟส | stages |
|---|---|
| `build` | research → selection → script → assets → video → captions |
| `publish` | social_posts → publishing (แยก workflow ต่อแพลตฟอร์ม) |

**Publish platforms:** `youtube` → `tiktok` → `facebook` (สั่งทีละตัวด้วย `--platform` หรือสั่งรวมให้โพสต์ที่เหลือ)

**โฟลเดอร์:** `research, source_data, scripts, images, assets, audio, videos, captions, social_posts, publishing, metadata, logs, final`

**Keys ใน .env (ค่าเริ่มต้น = ฟรี 100%):**
- `VIDEO_PROVIDER=ffmpeg` — **ค่าเริ่มต้น**: ประกอบวิดีโอที่เครื่อง (free, ไม่ต้องใช้ key) ผ่าน `shared/tools/video_builder.py`
- `SHOPEE_AFFILIATE_API_BASE_URL / APP_ID / APP_SECRET / PARTNER_ID / PARTNER_KEY` — สำหรับ `shopee_research.py` (ค้นสินค้า extra commission + ขายดี) **ต้องมีบัญชี Shopee Affiliate ที่อนุมัติ + ขอ whitelist Affiliate Open API ก่อน** (error 10035 ถ้ายังไม่ได้) — ตอนนี้ยังไม่มี keys ได้
- `YOUTUBE_CLIENT_ID/SECRET/REFRESH_TOKEN/CHANNEL_ID`, `TIKTOK_CLIENT_KEY/SECRET/ACCESS_TOKEN/OPEN_ID`, `FACEBOOK_APP_ID/SECRET/PAGE_ID/PAGE_ACCESS_TOKEN` — ใช้ตอนต่อแพลตฟอร์มโพสต์
- *(ไม่บังคับ)* `FAL_KEY`, `REPLICATE_API_TOKEN`, `RUNWAY_API_KEY`, `HEYGEN_API_KEY`, `IMAGE_PROVIDER` — API AI แบบเสียเงิน เก็บไว้ใน comment เท่านั้น ยังไม่จำเป็น

### 8.2 E-book (`ebook`)

**สายการผลิต (stages):**
```
research → outline → chapter_writer → editor → fact_check → cover_images → epub → pdf → publishing
```

**เฟส (phases):**
| เฟส | stages |
|---|---|
| `build` | research → outline → chapter_writer → editor → fact_check → cover_images → epub → pdf |
| `publish` | publishing (ขั้นเดียว ไม่มี --platform) |

**โฟลเดอร์:** `research, outline, chapters, editing, fact_check, images, cover, epub, pdf, publishing, metadata, logs, final`

**Keys ที่รองรับใน .env:** `EBOOK_PUBLISHING_API_KEY`

---

## 9. เส้นทางข้อมูลและ Artifact

### 9.1 `metadata/product.json` (ข้อมูลหลักของสินค้า)

| ฟิลด์ | ความหมาย |
|---|---|
| `product_name`, `slug`, `factory` | ข้อมูลพื้นฐาน |
| `status` | CREATED / PROCESSING / DRAFT_READY / APPROVED / REJECTED / PUBLISHED / FAILED |
| `phase` | `''` → `build` → `publish` |
| `review` | `{status: pending/approved/rejected, notes, at}` |
| `published` | รายชื่อแพลตฟอร์มที่โพสต์แล้ว (เช่น `["youtube","tiktok","facebook"]`) |
| `jobs[]` | ประวัติ job (id, workflow, status, stages, error) |
| `artifacts[]` | รายการ artifact (dedupe อัตโนมัติ ไม่ซ้ำข้ามรอบ) |

### 9.2 ข้อมูลที่ถูกสร้าง/อัปเดตเมื่อรัน workflow

| คำสั่ง | workflow ไฟล์ | artifact ตัวอย่าง |
|---|---|---|
| `test` | `workflows/test.json` | `research/test.txt`, `scripts/test.txt` (3 stage แรก) |
| `build` | `workflows/build.json` | `research/build.txt`, `source_data/selection.txt` (ข้อมูลสินค้าจาก export), **`scripts/script.txt` (สคริปต์โปรโมตจริง: สรรพคุณ/ราคา/โปรโมชัน)**, `assets/assets.txt`, **`videos/promo.mp4` (วิดีโอจริงจาก ffmpeg ฟรี + เสียงพากย์จากสคริปต์)**, `captions/captions.txt` (Shopee) / `chapters/build.txt`, `pdf/build.txt` (ebook) |
| `publish --platform youtube` | `workflows/publish-youtube.json` | `social_posts/youtube.txt`, `publishing/youtube.txt` |
| `publish --platform tiktok` | `workflows/publish-tiktok.json` | `social_posts/tiktok.txt`, `publishing/tiktok.txt` |
| `publish --platform facebook` | `workflows/publish-facebook.json` | `social_posts/facebook.txt`, `publishing/facebook.txt` |
| `publish` (ebook) | `workflows/publish.json` | `publishing/publish.txt` |

ทุกครั้งที่รัน: อัปเดต `products\<slug>\logs\workflow.json` + `metadata/product.json` + log ระดับโปรเจกต์ (`logs\factories\factories.jsonl` สำเร็จ / `logs\errors\errors.jsonl` ล้มเหลว)

> **กันทับข้อมูลจริง:** stage ที่ยังเป็น placeholder จะเขียนไฟล์เฉพาะเมื่อไฟล์ยังไม่มี หรือยังเป็น placeholder เดิม (ขึ้นต้น `Factory=`) — ข้อมูลจริงที่ export จาก `shopee_research.py` (`source_data\selection.txt`) หรือวางเองจะ**ไม่ถูกเขียนทับ**ตอน build → สคริปต์/วิดีโอใช้ข้อมูลจริงเสมอ

---

## 10. การดู Log และตรวจสอบระบบ

### 10.1 ดู log ของ Gateway แบบ realtime

```powershell
Get-Content C:\AI_FACTORY\shared\hermes_home\logs\gateway.log -Wait
```

ใช้เป็นอันดับแรกเมื่อ bot ไม่ตอบหรือไม่ connect

### 10.2 ตรวจสอบสถานะ Gateway

```powershell
Get-Content C:\AI_FACTORY\shared\hermes_home\gateway_state.json
```

ดูว่า `gateway_state` เป็น `running` และ `platforms.telegram.state` เป็น `connected` หรือไม่

### 10.3 ดูประวัติการทำงานของโรงงาน

```powershell
Get-Content C:\AI_FACTORY\logs\products\products.jsonl   # ประวัติสร้างสินค้า + review
Get-Content C:\AI_FACTORY\logs\factories\factories.jsonl # ประวัติ job สำเร็จ
Get-Content C:\AI_FACTORY\logs\errors\errors.jsonl       # ประวัติ error
```

### 10.4 ดูว่า Hermes ใช้ model ตัวไหนอยู่

- **ตอนเริ่ม session (terminal):** บรรทัด `🤖 AI Agent initialized with model: <model>` = ตัวที่ใช้จริง; ถ้าถูก fallback จะเห็น `🔄 Fallback model: <model> (<provider>)`
- **ระหว่าง session:** พิมพ์ `/status` → บรรทัด `Model: <model> (<provider>)` (เช่น `nvidia/nemotron-3-ultra-550b-a55b:free (openrouter)` = primary, `gemini-3.6-flash (gemini)` = fallback ชั้น ⑫)
- ใช้ 2 จุดนี้เช็คก่อนเสมอ ถ้าสงสัยว่าระบบใช้ model ไหนอยู่

### 10.5 วิธีเช็คว่า bot ตอบผ่านชั้นไหน (fallback)

เมื่อชั้นหลัก (`nvidia/nemotron-3-ultra-550b-a55b:free` ผ่าน openrouter — ชั้น ①) ใช้ไม่ได้ ระบบจะไล่ fallback ตามลำดับใน `config.yaml` — ดูจาก `agent.log` ว่า turn ไหนตอบด้วยโมเดล/provider ตัวไหนจริง:

**วิธีที่ 1 — ดู `agent.log` (แม่นสุด):**

```powershell
Get-Content C:\AI_FACTORY\shared\hermes_home\logs\agent.log -Tail 50 | Select-String "turn:|API call #1:|Fallback activated"
```

ตัวอย่างบรรทัดจริงที่ควรเห็น:

```
turn: session=20260809_184342_c31a0899 model=upstage/solar-pro4:free provider=nous platform=telegram
API call #1: model=upstage/solar-pro4:free provider=nous in=25196 out=85 total=25281 latency=9.6s
Fallback activated: nvidia/nemotron-3-ultra-550b-a55b:free → nvidia/nemotron-3.5-lightning:free (openrouter)
```

| บรรทัดใน log | ความหมาย |
|---|---|
| `turn: ... model=X provider=Y platform=telegram` | turn นี้ใช้โมเดล/provider ไหน (Y = `gemini` / `nous` / `openrouter`) |
| `API call #1: model=X provider=Y ... latency=Zs` | เรียก API จริงไปตัวไหน + ใช้เวลากี่วิ |
| `Fallback activated: A → B (provider)` | ชั้น A ล้ม กำลังสลับไปชั้น B |

**วิธีที่ 2 — ดู chain ปัจจุบัน:**

```powershell
& $hermes fallback list
```

ควรเห็น primary (`openrouter`: `nvidia/nemotron-3-ultra-550b-a55b:free`) + fallback 11 ชั้น ตรงกับ config: `openrouter` × 7 (`nemotron-3.5-lightning:free` → `laguna-s-2.1:free` → `nemotron-3-super-120b-a12b:free` → `north-mini-code:free` → `gpt-oss-20b:free` → `nano-omni-30b-a3b-reasoning:free` → `gemma-4-26b-a4b-it:free`) → `nous` × 3 (`solar-pro4:free` → `hy3:free` → `stepfun:free`) → `gemini` (`gemini-3.6-flash`) — ถ้าลำดับ/โมเดลไม่ตรง config ให้รีสตาร์ท Hermes/Gateway (แก้ config แล้วต้อง restart เสมอ)

**วิธีที่ 3 — ทดสอบชั้นใดชั้นหนึ่งตรงๆ (ไม่ผ่าน chain):**

```powershell
# ทดสอบ Nous ฟรี (ชั้น ⑨-⑪)
& $hermes chat -q "ตอบว่า OK เท่านั้น" -Q --provider nous -m upstage/solar-pro4:free --max-turns 2

# ทดสอบ Gemini (ชั้น ⑫)
& $hermes chat -q "ตอบว่า OK เท่านั้น" -Q --provider gemini -m gemini-3.6-flash --max-turns 2
```

> 💡 หลังทดสอบเช็ค `agent.log` อีกทีเสมอว่า session นั้น `provider=nous` / `provider=gemini` จริง — เพราะถ้าชั้นที่ทดสอบล้ม "OK" ที่เห็นอาจมาจากชั้นถัดไปใน chain

**ตัวอย่างจริง (ทดสอบ end-to-end 14–15 ส.ค. 2026):**

*ชุดที่ 1 — ชั้นหลัก (ข้อความจริงใน Telegram: "ตอนนี้คุณใช้โมเดลอะไรอยู่"):*

```
inbound message:  platform=telegram user=Yoseph chat=1709297704 msg='ตอนนี้คุณใช้โมเดลอะไรอยู่'
conversation turn: session=20260809_184342_c31a0899 model=gemini-3.6-flash provider=gemini platform=telegram
API call #2:       model=gemini-3.6-flash provider=gemini in=25615 out=29 total=25644 latency=2.6s
response ready:    platform=telegram chat=1709297704 time=3.6s api_calls=1 response=91 chars
[Telegram] Sending response (91 chars) to 1709297704        ← gateway.log: ส่งถึงแชทจริง
```

*ชุดที่ 2 — fallback ชั้น 1 (ตอนนั้นลำดับ fallback ข้อ 1 = nous; บังคับ Gemini ล้มโดยลบ key ชั่วคราว → ตกไป Nous):*

```
inbound message:  platform=telegram msg='สวัสดี'
conversation turn: ... model=upstage/solar-pro4:free provider=nous platform=telegram
API call #1:       model=upstage/solar-pro4:free provider=nous in=25196 out=85 total=25281 latency=9.6s
response ready:    time=21.1s api_calls=1 response=116 chars
```

*ชุดที่ 3 — หลัง reorder chain + fix Telegram proxy (15 ส.ค. 2026): ตอบผ่าน primary ใหม่ OpenRouter lightning:*

```
inbound message:  platform=telegram user=Yoseph chat=1709297704 msg='สวัสดี'
conversation turn: ... model=nvidia/nemotron-3.5-lightning:free provider=openrouter platform=telegram
API call #1:       model=nvidia/nemotron-3.5-lightning:free provider=openrouter in=29928 out=124 total=30052 latency=13.1s
response ready:    platform=telegram chat=1709297704 time=113.6s api_calls=1 response=68 chars
[Telegram] Sending response (68 chars) to 1709297704        ← gateway.log: ส่งผ่าน proxy IPv4 (CONNECT api.telegram.org → 149.154.166.110)
```

→ สรุป: ชุด 1 ชั้นหลัก (ตอนนั้น = gemini) ตอบ 3.6s / ชุด 2 fallback (nous) ตอบ 9.6s / ชุด 3 primary ใหม่ (OpenRouter lightning ผ่าน proxy IPv4) API 13.1s — ทั้ง 3 เส้นทางทำงานจริงผ่าน Telegram; วิธีดูแบบนี้ใช้ได้กับทุกชั้น (เปลี่ยนไป grep `provider=openrouter` / `provider=nous` / `provider=gemini`)

*ชุดที่ 4 — E2E หลังแก้ watcher restart วน (16 ส.ค. 2026, 23:20): ตอบผ่าน primary OpenRouter Nemotron 3 Ultra — ยืนยันระบบนิ่ง:*

```
inbound message:   platform=telegram user=Yoseph chat=1709297704 msg='สวัสดี'
conversation turn: ... model=nvidia/nemotron-3-ultra-550b-a55b:free provider=openrouter platform=telegram
API call #1:       model=nvidia/nemotron-3-ultra-550b-a55b:free provider=openrouter in=34265 out=110 total=34375 latency=42.7s
response ready:    platform=telegram chat=1709297704 time=116.5s api_calls=1 response=98 chars
[Telegram] Sending response (98 chars) to 1709297704      ← ส่งถึงแชทจริง
```

เช็คประกอบ (หลัง turn จบ): watcher เงียบ (Connected คงเดิม 23:10:19 — ไม่มี restart ระหว่าง turn) ✅ — **ตัวอย่างนี้ยืนยันว่าหลังแก้ v11 ระบบนิ่งจริง** (ก่อนหน้า 22:31–23:09 watcher ฆ่า gateway วนทุก 2 นาที ข้อความเลยหาย)

### 10.6 ตัวอย่างข้อมูลที่เห็นใน log จริง (ณ วันที่ 9 ส.ค. 2026)

- Product ที่สร้างแล้ว: `Test-Product--Thai-สินค้า`, `Test-E-book`, `Failure-Test`, `Unicode-ไทย-Test`, `แก้วเก็บความเย็น`, `หูฟังบลูทูธ`
- Job สำเร็จ: `Test-Product--Thai-สินค้า`, `Test-E-book`, `หูฟังบลูทูธ`
- Error ที่บันทึก: `Failure-Test` (ebook) — error: `Intentional acceptance-test failure` (เป็นการทดสอบตั้งใจ)

---

## 11. สถานะปัจจุบันและแผนพัฒนา

### ✅ ทำได้แล้วตอนนี้
- สร้าง/จัดการ Product workspace แยกส่วนตามโรงงาน (รองรับชื่อภาษาไทย/Unicode)
- **Workflow 2 เฟส:** `build` (draft) → `review` (approve/reject + gate) → `publish`
- **Publish แยกแพลตฟอร์ม** สำหรับ Shopee (YouTube → TikTok → Facebook) พร้อมติดตาม `published[]` กันโพสต์ซ้ำ
- **ปุ่มยืนยันบน Telegram** (review approve/reject + ยืนยันโพสต์) ผ่าน clarify tool ของ Hermes
- **วิดีโอโปรโมต ฟรี 100%** — stage `video` ใน build ประกอบวิดีโอด้วย ffmpeg (`shared/tools/video_builder.py`): ภาพจาก `images/` + เอฟเฟกต์ Ken Burns + ชื่อสินค้า → `videos/promo.mp4` (ไม่มีค่าใช้จ่าย ไม่ต้องใช้ API)
- **สคริปต์จริง + Voiceover ฟรี** — stage `script` เขียนสคริปต์โปรโมต (สรรพคุณ/ราคา/โปรโมชัน) ลง `scripts/script.txt` (`script_writer.py`); วิดีโอพากย์ส่วน `[voiceover]` ของสคริปต์ด้วย Microsoft Edge TTS (`edge-tts`, อัตโนมัติไทย/อังกฤษ); ถ้าไม่มี edge-tts/อินเทอร์เน็ต วิดีโอยังสร้างได้แบบไม่มีเสียง
- **ค้นสินค้า Shopee ก่อนสร้าง Product** — `shopee_research.py` (Affiliate Open API `productOfferV2`): กรอง extra commission (AMS) + ยอดขายสูง แล้ว export ข้อมูลจริงลง product → สคริปต์/วิดีโอใช้ข้อมูลจริง (รอ keys + whitelist อยู่)
- คำสั่งตรวจสอบ: `status` / `artifacts`
- ตรวจสอบผ่าน log ทั้ง 3 ระดับ (products / factories / errors)
- สั่งงานผ่าน Terminal และ Telegram Bot (ด้วย skill `ai-factory` v1.14.0)

### 🚧 ยังไม่ทำ (ตามการออกแบบ)
- ยังไม่มี adapter จริงสำหรับ Shopee API, การโพสต์ YouTube/TikTok/Facebook, EPUB/PDF publishing → stage เหล่านั้นยังเขียน placeholder
- การ Gen วิดีโอ AI (Fal, Runway, HeyGen, Replicate) ยังไม่เปิดใช้งาน — ใช้ ffmpeg ท้องถิ่นฟรีแทน (ดูหัวข้อ 8.1)
- `integrations.example.json` ระบุชัดเจน: free local pipeline (ffmpeg) พร้อมใช้; paid API adapters intentionally not configured

### 🗺️ ขั้นตอนต่อไปที่แนะนำ
1. ตั้งค่าเฉพาะ keys ที่จำเป็นใน `.env` ของโรงงานนั้นก่อน (ตอนนี้ไม่ต้องใช้ key ใดเลยสำหรับวิดีโอ)
2. ทดสอบวิดีโอฟรี: ใส่ภาพสินค้าลง `products\<slug>\images\` แล้วรัน `build` → ได้สคริปต์จริงที่ `scripts/script.txt` + `videos/promo.mp4` พร้อมเสียงพากย์จากสคริปต์ (แก้สคริปต์แล้ว build ใหม่เพื่อเปลี่ยนเสียงพากย์ได้)
3. ต่อ Shopee Affiliate API ก่อน (ได้ภาพสินค้าจริง + ข้อมูลราคามาใส่ใน research/images)
4. จากนั้นค่อยเพิ่มการโพสต์จริงทีละแพลตฟอร์ม (YouTube ก่อน): เติม logic จริงใน `workflows/publish-youtube.json` (โครงสร้างพร้อมแล้ว)
5. (ไม่บังคับ) ถ้าอยากได้วิดีโอ AI จริงค่อยเปิด `FAL_KEY`/`REPLICATE_API_TOKEN` แล้วเปลี่ยน `VIDEO_PROVIDER`
6. เพิ่มโรงงานใหม่ได้โดยไม่แตะโค้ด manager: สร้าง `factories\<new-id>\config\factory.json` (มี phases + publish_platforms ได้) + workflows + .env

---

## 12. ข้อควรระวังด้านความปลอดภัย

- **ห้าม**ใส่ key ใดๆ ในโฟลเดอร์ product, log, README, หรือข้อความแชท
- ไฟล์ `.env` ทั้งหมดถูก Git ignore แล้ว (`*.env`, `*.env.*`) — อย่าเผลอ `git add -f`
- `products\` และ `archive\` เป็นข้อมูล ไม่ใช่โค้ด → ถูก ignore ด้วย
- ห้ามแชร์ log ที่มีลิงก์บัญชีส่วนตัวหรือ credentials
- ตรวจสอบ `TELEGRAM_ALLOWED_USERS` ให้มีแค่คนที่ไว้ใจได้เท่านั้น
- อย่าเปลี่ยน model ใน `config.yaml` โดยไม่ได้เช็คว่ามีอยู่จริงใน OpenRouter ก่อน
- `publish --force` ใช้ได้เฉพาะเมื่อ user ยืนยันชัดเจนว่าต้องการ bypass review gate

---

## 13. การแก้ปัญหาเบื้องต้น (Troubleshooting)

| อาการ | สาเหตุที่เป็นไปได้ | วิธีแก้ |
|---|---|---|
| `$hermes` ไม่รู้จัก | เปิดหน้าต่าง PowerShell ใหม่ | ตั้งตัวแปรใหม่ตามหัวข้อ 5.2 |
| Bot ไม่ตอบ / ไม่ connect | Gateway ไม่ได้รัน | รัน `schtasks /Run /TN "AI_Factory_Gateway"` (หรือเปิด `& $hermes gateway` ค้างไว้) + เช็ค `gateway.log`; ถ้า `state\gateway.lifecycle.json` ขึ้น `phase: exited` = Gateway ไม่รันแน่นอน (แม้ `gateway_state.json` จะบอก `running` ก็ตาม — ไฟล์นั้นอาจค้างข้อมูลเก่า) |
| Gateway ถูกฆ่าแล้วไม่กลับมาเอง | ฆ่าไปถึงขั้น watchdog (ทั้ง wscript/cmd/bat) หรือรันแบบ manual (วิธี B) | ถ้าฆ่าเฉพาะตัว Gateway (`python.exe` จาก `lifecycle.json`) watchdog จะรีรันให้เองภายใน ~30 วิโดยไม่ต้องทำอะไร; ถ้าไม่กลับมา = ฆ่าถึงขั้น watchdog แล้ว → รัน `schtasks /Run /TN "AI_Factory_Gateway"` ใหม่ (หรือ `& $hermes gateway`) |
| ไม่เห็น `telegram connected` | Token ผิด หรือถูก rate-limit | เช็ค `TELEGRAM_BOT_TOKEN`, ลองรันใหม่ |
| สร้างสินค้าแล้ว error `FileExistsError` | slug ซ้ำกับที่มีอยู่ | เปลี่ยนชื่อสินค้า หรือลบโฟลเดอร์เดิม |
| `Product/factory mismatch` | ส่ง `--product` ผิดโรงงาน | รัน `list` ดู factory ที่ถูกต้องของ product นั้น |
| publish → `ok: false` "not approved" | ยังไม่ได้ review approve | รัน `review --status approve` (หลัง build) |
| publish → `ok: false` "no build draft" | ยังไม่เคย build หรือ build ล้มเหลว | รัน `build` ก่อน แล้ว review แล้วค่อย publish |
| publish → `ok: false` "already published" | แพลตฟอร์มนี้โพสต์ไปแล้ว | ใช้ `--platform` ตัวที่เหลือ หรือ build ใหม่เพื่อทำ draft ใหม่ |
| publish → `ok: false` "Unknown platform" | พิมพ์ชื่อแพลตฟอร์มผิด | ดูรายการใน error หรือ `list` (youtube/tiktok/facebook) |
| review approve → `ok: false` | สินค้ายังไม่เคย build (CREATED) | ต้อง `build` ให้เป็น DRAFT_READY ก่อน |
| Job ติด `FAILED` | stage พัง (หรือรันด้วย `--fail`) | อ่าน `products\<slug>\logs\workflow.json` และ `logs\errors\errors.jsonl` |
| export แล้วภาพสินค้าไม่ขึ้น (`"image": "skipped: …"`) | ไม่มี `image_url` / ลิงก์ตาย / URL คืน HTML / ไฟล์ใหญ่เกิน 5MB | ดูเหตุผลจาก field `image` ในผลลัพธ์ export: `no image_url` = สินค้าไม่มีรูป, `response is not an image` = URL คืนหน้า HTML, `too large` = เกิน 5MB, `URL error/HTTP …` = ลิงก์ตายหรือถูกบล็อก — วิดีโอจะใช้ title card แทน; ถ้าอยากได้รูปจริง วางไฟล์ภาพเองที่ `products\<slug>\images\` แล้วรัน build ใหม่ |
| Hermes ใช้ skill/config เก่า | แก้ skill แล้วไม่รีสตาร์ท | ออกจาก Hermes แล้วเปิดใหม่ (เพื่อโหลดปุ่ม clarify ใหม่) |
| Fallback ทั้งหมด (Gemini+Nous+OpenRouter) ล้มแล้ว Hermes **ค้าง/ไม่ตอบ** (ไม่ข้ามไปตัวถัดไป) | ตัว fallback ที่ resolve ได้แต่ server ไม่พร้อม (API timeout) — fallback เลือกตามลำดับ config และ **ไม่ข้าม** ตัวที่ค้าง (timeout × retries) | ตรวจว่า key ของชั้นนั้นยัง valid อยู่ (OpenRouter / Nous / Gemini) — revoke แล้วจะวน timeout |
| ปุ่มไม่ขึ้นใน Telegram | Hermes ยังไม่ได้โหลด skill ใหม่ หรือ clarify tool ไม่ว่าง | รีสตาร์ท Hermes; เช็คว่า default toolset มี clarify |
| ชื่อสินค้าไทย/Unicode ใช้ได้ไหม | ได้ — slug รองรับ Unicode | เช็ค path ใน JSON output อย่าใช้ path ที่ผิดพลาด |
| ไม่เห็น Gemini ถูกใช้ (ปกติ primary = openrouter ultra; gemini เป็นชั้น ⑫ — จะใช้เมื่อชั้น ①-⑪ ล้ม) | ยังไม่ใส่ `GEMINI_API_KEY` หรือ key ผิด/ถูก revoke | ตรวจ `shared\hermes_home\.env` มี `GEMINI_API_KEY=AIza...` ถูกต้อง → รีสตาร์ท Hermes (ดูหัวข้อ 5.3) |
| เปิด Hermes แล้วขึ้น `No inference provider is configured yet` + ถาม `Set up a provider now?` | ยังไม่มี key ของ provider ไหนเลย (primary = OpenRouter ต้องมี `OPENROUTER_API_KEY` ใน .env) — Hermes ตรวจ primary ก่อน | พิมพ์ `n` เพื่อข้าม → ระบบใช้ provider ฟรีที่เหลือต่อได้ตามปกติ (fallback); พอใส่ key แล้วจะไม่ขึ้นอีก (ดูหัวข้อ 5.3) |
| `-z`/`--oneshot` error `No usable credentials found for provider ...` | โหมด one-shot ไม่ผ่าน fallback chain (ต่างจากโหมดคุยปกติ) — ใช้ primary โดยตรง | ตรวจว่า `OPENROUTER_API_KEY` อยู่ใน .env หรือ override: `& $hermes -z "<prompt>" --provider openrouter -m "nvidia/nemotron-3-ultra-550b-a55b:free"` |
| `gemini-3.6-flash` error (404 / model not found) | model id ไม่ตรงกับที่ Google เปิดให้บัญชีนี้ | แก้ `config.yaml` → `default: gemini-2.5-flash` (หรือ `gemini-3-flash`) หรือรัน `& $hermes model` เลือกใหม่ |

---

## 14. Changelog

### v13 — 19 ส.ค. 2026 (แก้ bat loop guard — gateway ค้างหลัง plugin discovery + proxy ซ้อน 6 ตัว)

- **อาการ:** bot ไม่ทำงาน — gateway ค้างหลัง plugin discovery (ไม่มี log ใหม่ 10+ นาที) + proxy 8899 มี 6 ตัวซ้อนกัน + bat loop watchdog restart วน 6 ครั้ง → gave up (exit 1) → ไม่มี self-heal
- **ต้นตอ ① Gateway ค้างหลัง boot:** gateway boot ช้าบนเครื่อง RAM ต่ำ (plugin discovery + SQLite init) → เขียน heartbeat ครั้งแรกไม่ทัน → bat loop guard (`check-gateway-running.ps1`) ใช้ CIM query ช้า (5-10s) → timeout → ไม่เห็น gateway → start ซ้ำ → Telegram ชนกัน → exit code 1
- **ต้นตอ ② Proxy ซ้อน 6 ตัว:** bat loop `ensure_proxy` เช็ค port 8899 ว่ามีคนฟัง → มีแล้ว → แต่ proxy จริง die ระหว่างนั้น → bat loop start ใหม่ทุก loop → 6 ตัวซ้อน (SO_REUSEADDR) → proxy จริงถูก replace ด้วยตัวที่ไม่ทำงาน
- **แก้:** (1) **`check-gateway-running.ps1` v2** — อ่าน `lifecycle.json` ก่อน (<1ms) แทน CIM query (5-10s); fallback CIM ถ้า file หาย/stale → guard เร็วขึ้น 10x (0.5s vs 5s) → ไม่พลาด detect gateway ที่กำลัง boot (2) ฆ่า proxy 6 ตัว → เหลือ 1 ตัว (clean start) (3) kill gateway ค้าง + restart ผ่าน Task Scheduler → Telegram connected สำเร็จ
- **บทเรียน:** ⚠️ CIM query (`Get-CimInstance Win32_Process`) ช้ามากบนเครื่อง RAM ต่ำ (<1GB free) — ใช้ file-based check (lifecycle.json) เร็วกว่า 10x; และ**อย่าเช็ค port ว่ามีคนฟังแล้วเชื่อว่า proxy ทำงาน** — ต้อง probe จริง (TCP connect + read) ไม่งั้นจะเจอ zombie process

### v12 — 17 ส.ค. 2026 (ลบ LM Studio ออกจาก fallback chain — เหลือ API เท่านั้น)

- **การตัดสินใจ:** ไม่เอา Local AI (LM Studio เครื่องนี้ ⑭ — qwen3-1.7b, CPU-only) และไม่เอาผ่าน Tailscale (LM Studio เครื่องทำงาน ⑬ — qwen3.5-9b) — เหลือ **แค่ API** (OpenRouter + Nous + Gemini)
- **config.yaml:** ลบ 2 ชั้นสุดท้ายออกจาก `fallback_providers` (`custom` @ `100.77.88.33:1234` + `lmstudio` @ `127.0.0.1:1234`) + ลบ `custom_providers` ทั้งหมด (`lmstudio-work` / `lmstudio-local`) → chain 14 → **12 ชั้น** (openrouter × 8 → nous × 3 → gemini) — ไม่ต้องพึ่ง Tailscale/เครื่องทำงานอีก
- **ไฟล์ที่ลบ:** `shared/tools/lmstudio-alert.py` (alert 🐌 เมื่อตกถึงชั้น lmstudio) + `shared/hermes_home/lmstudio-watch.ps1` (idle-based unload/load) — ลบการเรียก alert ออกจาก `gateway-watch.ps1` (section 0.5) ด้วย
- **Task ที่ลบ:** `HermesLMStudioWatch` (ตรวจแล้วไม่มีอยู่แล้วบนเครื่องนี้ — ตอนนี้ clean) + **`LMStudioWatch`** (ยังเหลืออยู่บนเครื่องนี้ — ลบแล้ว)
- **ปิด LM Studio สนิท (17 ส.ค. 2026):** unload โมเดล (RAM คืนแล้ว — `No models loaded`) → kill `LM Studio.exe --run-as-service` + children (`taskkill /F /IM "LM Studio.exe" /T`) → port 1234 หลุด → `settings.json` มี `enableLocalService: false` (จะไม่ฟื้นตอน boot) → ตรวจ Registry Run / Startup folder / Task Scheduler / services ไม่มี autostart LM Studio เหลือ — ⚠️ ระวัง: `LMS.exe` (Intel Management service) เป็นคนละตัวกับ LM Studio — อย่าแตะ
- **ผลดี:** ไม่ต้องเปิด/ดูแล LM Studio อีก (ประหยัด RAM ~1.3GB), ไม่พึ่งเครื่องทำงาน (ถ้าปิด chain ก็ยังอยู่ได้), `hermes fallback list` เหลือ 11 fallback (เร็วขึ้น)
- **docs:** Workthrough (chain 12 ชั้น + §10 วิธีเช็ค + troubleshooting) · SYSTEM-OVERVIEW · FALLBACK-AI-SETUP · Quick-Start · README — ลบ reference LM Studio/Tailscale ทั้งหมด; ตัวอย่าง E2E เก่า (ชุด 1-4) ที่อ้างชั้น ⑬⑭ เก็บไว้เป็นประวัติ
- **ประวัติ (เก็บไว้):** v9 (ทดสอบ lmstudio — เลือกชั้นถูกแต่ CPU-only ช้าเกินจริง), v10 (alert ตกถึง lmstudio), v8 (idle-based unload/load) — อ่านเพื่อเรียนรู้ว่าทำไมถึงถอดออก

### v12.1 — 17 ส.ค. 2026 (ยุบ Health Check เข้า Fallback Watch + ลบ Tailscale check)

- **ลบ Tailscale ออกจาก health-check:** ระบบ API-only แล้ว — ตัด `Tailscale` section ออกจาก `health-check.ps1` (เหลือตรวจ 7 จุด: heartbeat/process/log+Telegram/chain/task/.env keys/errors)
- **Health Check แจ้งเฉพาะตอนเปลี่ยนโมเดล (ยุบรวม):** เอา task `HermesHealthCheck` (ทุก 30 นาที) ออก — `fallback-watch.ps1` (ทุก 1 นาที) เมื่อเจอ `Fallback activated` จะเรียก `health-check.ps1 -Compact` (เพิ่ม switch ใหม่: print เฉพาะ CRIT/WARN) แล้ว**แนบสถานะระบบไปในข้อความแจ้งเตือนเดียวกัน** — ระบบปกติ (ไม่มี fallback) จะเงียบสนิท ไม่มี health report ทุก 30 นาทีอีก
- **Gateway self-heal ยังทำงานเต็มรูปแบบ (ไม่ลด):** health-check/fallback-watch เป็น **read-only** (ไม่แตะ gateway) — watcher (`gateway-watch`) + bat loop ยังคอย restart กัน bot เงียบตามเดิม; การยุบ Health Check แค่ลดการแจ้งเตือน ไม่แตะกลไกกู้คืน
- **ไฟล์ที่ลบ:** `install-healthcheck-task.ps1` + task `HermesHealthCheck` (ลบจริง); `install-tasks.ps1` ตัด block health-check ออก
- **ทดสอบจริง:** `health-check.ps1 -Compact` → แสดงเฉพาะ WARN/CRIT ✅ / `fallback-watch.ps1 -TestSend` → ส่งพร้อม 🧪 สถานะระบบแนบ ✅ (ข้อความทดสอบใน Telegram)

### v11 — 16 ส.ค. 2026 (แก้ watcher restart วน — กัน 2 กลไกกู้คืนชนกัน)

- **อาการ (เจอระหว่าง E2E 22:31–23:09):** watcher (`HermesGatewayWatch`) restart gateway **วนทุก 2 นาทีไม่หยุด** — bot ตอบได้แต่ถูกฆ่ากลางทางตลอด; `gateway-watch.log` เต็มไปด้วย `WATCH: heartbeat เก่า ... -> restart`
- **① 2 กลไก restart แข่งกัน:** `start_gateway.bat` (spawn gateway เอง + คอย restart ตัวมันเอง) กับ watcher (เดิมทำ `schtasks /run` start task ซ้อน) → **2 bat + 2 gateway เขียน heartbeat ไฟล์เดียวกัน** → JSON เพี้ยน → watcher parse ล้ม → เห็น "heartbeat เก่า" → restart ซ้ำ วนไม่จบ — **แก้: watcher ฆ่า gateway ค้างเท่านั้น แล้วปล่อยให้ bat loop ตัวเดียวที่รออยู่ restart เอง** (ไม่ start task ซ้อน — ใช้ task เป็น backup เฉพาะตอนไม่มี bat loop)
- **② watcher ฆ่า gateway ที่สด (race condition):** gateway เขียน heartbeat แบบ truncate+write (**ไม่ atomic**) → watcher อ่านเจอไฟล์ครึ่งเดียว → JSON เพี้ยน → parse ล้ม → "heartbeat เก่า" ผิด ๆ (log แสดง age ว่างเปล่า `( วิ)`) → **ฆ่า gateway ที่ทำงานปกติ** — แก้: **อ่าน heartbeat แบบ retry 3 ครั้ง (ห่าง 1 วิ)** รอให้เขียนเสร็จ + `$BootGraceSec` 180→**300** (RAM เต็ม boot ช้า เขียน heartbeat ครั้งแรกช้า)
- **ยืนยัน:** หลังแก้ watcher เงียบ 2 รอบติด (ไม่มี "ฆ่า" ใหม่) + Connected คงเดิม + heartbeat สดต่อเนื่อง ✅ (E2E "สวัสดี" ตอบผ่าน openrouter 214 chars ส่งถึง + alert lmstudio ไม่ปลอม)
- **บทเรียน:** ระบบนี้มี **2 กลไกกู้คืนที่ต้องไม่ชนกัน** — bat loop = restart หลัก (ตัวเดียว) / watcher = ฆ่า gateway ค้าง + self-heal proxy เท่านั้น; และ**อย่าอ่านไฟล์ state ที่เขียนแบบไม่ atomic โดยไม่ retry** (partial write → ตัดสินใจผิด → ฆ่า process ที่ปกติ)

### v10 — 16 ส.ค. 2026 (แจ้งเตือน Telegram เมื่อ fallback ตกถึงชั้น lmstudio ⑭)

- **ปัญหา:** ชั้น ⑭ (qwen3-1.7b, CPU-only) ช้ากับ session context ใหญ่ — ทดสอบ v9 พบว่าประมวลผล 31K tokens นานกว่า 15 นาที → hermes ตัด stream (`Stream stale for 900s`) → bot เงียบโดยไม่มีใครรู้
- **แก้:** สร้าง `shared/tools/lmstudio-alert.py` (stdlib-only) — อ่าน `logs/agent.log` หา turn ที่ match `conversation turn: ... provider=lmstudio` → ส่ง Telegram แจ้งเตือน 🐌 1 ครั้งต่อ turn (state file `.lmstudio_alert_state.json` กันส่งซ้ำ + retry ถ้าส่งไม่สำเร็จ — pattern เดียวกับ watchdog_notify.py); เรียกจาก `gateway-watch.ps1` ทุก 2 นาที (ผ่าน HermesGatewayWatch — ไม่ต้องสร้าง task ใหม่)
- **ข้อความแจ้ง:** `🐌 Bot ตกถึงชั้นสุดท้าย (LM Studio ⑭ — qwen3-1.7b, CPU-only)! ตอบอาจช้าเป็นนาที หรือเกิน 15 นาทีจนถูกตัด — ถ้าไม่เร่งด่วน รอ/ส่งใหม่ก็ได้` + timestamp + ข้อความที่ user ส่ง
- **ทดสอบจริง:** baseline (ไม่ส่งย้อนหลัง) ✅ / ส่งจริง `ok=True` ✅ / รันซ้ำไม่ส่งซ้ำ ✅ / syntax PS1 ผ่าน ✅
- **หมายเหตุ:** alert ทำงานเฉพาะ turn ที่ **เริ่ม** ด้วย lmstudio (มองเห็นตั้งแต่ชั้นแรก) — ไม่ใช่ตอน fallback ระหว่าง turn; ถ้าต้องการจับตอน fallback ระหว่าง turn ต้องดู log API call ที่ provider เปลี่ยน (ยังไม่ได้ทำ — ปกติ hermes fallback ระหว่าง turn เร็วพอ)
- **อ้างอิง:** ปัญหา watcher restart วนที่เจอระหว่าง E2E → แยกบันทึกไว้ใน **v11**

### v9 — 16 ส.ค. 2026 (ทดสอบบังคับ fallback ไปชั้น lmstudio ⑭ — ผล: เลือกถูก แต่ช้าเกินจริง)

- **เป้าหมาย:** ยืนยันว่า bot ตอบผ่านโมเดล 32K (qwen3-1.7b) ของเครื่องนี้ได้จริง เมื่อปิดชั้นบนทั้งหมดชั่วคราว
- **วิธีบังคับรอบแรก (ผิด — ล้มทันที):** comment `OPENROUTER_API_KEY` + `GEMINI_API_KEY` ใน `.env` + ย้าย `auth.json` ออก แล้ว restart → turn ล้ม `RuntimeError: No LLM provider configured` ตอน init — **บทเรียน: primary ใน `config.yaml` ยังชี้ openrouter แต่ key หาย → hermes init ต้องการ primary ที่มี key ใช้งานได้ → fallback chain ทำงานตอน API call (ระหว่าง turn) ไม่ใช่ตอน init** — วิธีปิดชั้นบนด้วยการเก็บ key ไม่เวิร์ก
- **วิธีบังคับรอบสอง (ถูก):** กู้คืน `.env`/`auth.json` ครบ + แก้ `config.yaml` ชั่วคราว: `model.provider: lmstudio`, `model.default: qwen/qwen3-1.7b`, `fallback_providers: []` → restart → turn เริ่มผ่าน `provider=lmstudio` จริง (`conversation turn: ... model=qwen/qwen3-1.7b provider=lmstudio` 21:53:10 + `OpenAI client created ... base_url=http://127.0.0.1:1234/v1` 21:55:03)
- **ผล: เลือกชั้นถูก แต่ตอบไม่ทัน:** llama-server ประมวลผลจริง (CPU เพิ่ม 208→837 ต่อเนื่อง ~11 นาที) แต่ **session เก่ามี context ~31,700 tokens** (คุยกันมาทั้งวัน) + โมเดล 1.7B รัน **CPU-only** (เครื่องนี้ไม่มี GPU) + **RAM เหลือ 0.3GB** (freebuff + chrome กิน) → ประมวลผลนานกว่า 15 นาที → hermes ตัด stream (`Stream stale for 900s (threshold 900s) — no chunks received. Killing connection.` 22:10:04) → fallback ว่าง → ไม่มีคำตอบ
- **บทเรียน:** ชั้น ⑭ ใช้ได้จริงในแง่ "hermes เลือกถูก + ต่อ LM Studio ได้" แต่เหมาะเป็น **ฉุกเฉินสุดท้าย กับข้อความสั้นๆ (session ยังไม่ยาว) เท่านั้น** — ไม่เหมาะกับ session context ใหญ่บน CPU-only → **ลำดับ fallback ปัจจุบัน (lmstudio เป็นชั้นสุดท้าย) ถูกต้องแล้ว ไม่ต้องแก้**
- **กู้คืนครบ:** config.yaml เดิม (primary=openrouter + fallback 13 ชั้น) + `.env`/`auth.json` + restart ผ่าน task → `Connected to Telegram` 22:17:21 + heartbeat สด + proxy 8899 ฟัง + `hermes fallback list` ยืนยัน chain 14 ชั้น ✅ (ลบ backup ชั่วคราว lmtest แล้ว)

### v8 — 16 ส.ค. 2026 (LM Studio โหลดเฉพาะเมื่อจำเป็น — idle-based)

- **ปัญหา:** เครื่อง RAM 7.9GB เต็มง่าย → gateway OOM ตายกลาง turn (เจอจริงตอน turn "สวัสดี": ตายตอน API call #20, context 124K+) — ตัวกิน RAM: freebuff 786MB + **llama-server (LM Studio ⑭) 229MB+ (โมเดล 1.28GB ค้างใน memory ทั้งวัน)** + chrome/msedge หลายตัว
- **ข้อเท็จจริง:** ชั้น ⑭ ถูกใช้ครั้งสุดท้ายเมื่อ 11 ส.ค. (5 วัน) แต่ LM Studio auto-start ตอน login (`Registry --run-as-service`) + watcher keep-alive ตลอด → รันทิ้งทั้งวัน
- **แก้:** (1) **ลบ auto-start ตอน login** (Remove-ItemProperty Registry) (2) **`lmstudio-watch.ps1` ใหม่แบบ idle-based** — bot เงียบ 30 นาที (`$IdleUnloadMin=30`) → `lms unload` คืน RAM ~1.3GB / มี turn ใหม่ → `lms load -c 32768` กลับอัตโนมัติ; ตรวจ activity จาก `agent.log` บรรทัด `conversation turn` ล่าสุด (3) server port 1234 รันตลอด (ตัวรับคำสั่งเบาๆ) — ไม่กระทบ fallback
- **บั๊กที่เจอระหว่างทำ:** `lmstudio-watch` เดิมวน "server ตาย → start ใหม่" ทุก 2 นาที (19:37–19:55) ทั้งที่ server รันปกติ — ต้นตอ: `lms server status` เขียน output ไป **stderr** + `$ErrorActionPreference='SilentlyContinue'` กลืนเป็น NativeCommandError → match `'running'` ไม่ติด → วนตลอด — **ทางแก้: เช็ค TCP port 1234 ตรงๆ (TcpClient) แทน parse ข้อความ** (วิธีเดียวกับ proxy)
- **บั๊กที่เจอหลัง deploy (verify):** watcher โหลดด้วย `-c 65536` → `lms load` ล้มทุกครั้ง (`Engine protocol runtime llama-server exited before becoming healthy`) → วน "โหลดยังไม่สำเร็จ" — ต้นตอ: qwen3-1.7b native context = **32K** (config.yaml ก็ใช้ `context_length: 32768`) → แก้เป็น `-c 32768` (โหลดผ่าน 25.8s) + เพิ่ม **guard กัน task ซ้อน** (task รันทุก 2 นาที + load ใช้เวลา ~30-100s + `Stop If Still Running: Disabled` → 2 instance ชนกัน → load ล้ม)
- **ทดสอบจริง:** unload อัตโนมัติ (log: `bot เงียบ 9 นาที -> unload qwen/qwen3-1.7b (คืน RAM)` + `unload สำเร็จ` + โมเดลหลุดจาก memory) ✅ / โหลดกลับอัตโนมัติ (`มี turn ใหม่ -> โหลด` → โมเดลกลับ IDLE 1.28GB @ 32768 context — `-c 65536` ล้ม, `-c 32768` ผ่าน) ✅ / หลังแก้: watcher เงียบ (ไม่วน), โมเดลอยู่ @ 32K, task รอบใหม่รันปกติ ✅
- **หมายเหตุ:** เครื่องทำงานยังใช้ `work-lmstudio-autostart.ps1` (โหลดตอน login ตามเดิม — งานหนัก ต้องพร้อมเสมอ) — idle-based ใช้เฉพาะเครื่องนี้ (fallback ฉุกเฉิน)

### v7 — 16 ส.ค. 2026 (กู้ bot เงียบ 5+ ชม. + self-heal proxy / กัน double gateway)

- **อาการ:** bot ไม่ตอบเลยเป็นเวลานาน (18:36+ วน `ConnectError: All connection attempts failed`) — gateway รันอยู่ + heartbeat สด แต่ Telegram ต่อไม่ได้
- **ต้นตอ ① Proxy ตาย (port 8899):** `telegram-ipv4-proxy.py` (ตัวบังคับ IPv4) ถูก start **แค่ครั้งเดียวตอน bat เริ่ม** — loop watchdog restart เฉพาะ gateway ไม่แตะ proxy → proxy ตายตอน ~13:02 แล้วไม่มีใคร start ใหม่ → bot วน retry ไปเรื่อยๆ 5+ ชม.
- **ต้นตอ ② Double gateway (ซ้อนหลายตัว):** `HermesGatewayWatch` (ทุก 2 นาที) + `start_gateway.bat` (watchdog loop) ต่าง restart gateway ผ่านคนละทาง → gateway 2 ตัว (เคยเห็น 6 ตัว) → **Telegram 409 conflict** (poll token เดียวกัน 2 ตัว)
- **ต้นตอ ③ Lock ค้างหลัง kill แบบ force:** `taskkill /F` ฆ่า gateway ทิ้งไว้ `gateway.lock`/`.dispatcher.lock` → ตัวใหม่ค้างตอน boot (ต้องลบ lock ก่อน start)
- **ทางแก้ (self-heal + guard):**
  1. `start_gateway.bat` — ย้าย proxy check ไปเป็น subroutine `:ensure_proxy` (เช็ค port 8899 → ถ้าตาย start ใหม่) เรียก **ก่อน guard และทุก loop** → proxy ฟื้นเองทุกครั้งที่ restart gateway
  2. guard กันรันซ้ำ เปลี่ยนจากเช็ค PID เดียว → เช็ค process จริงผ่าน `check-gateway-running.ps1` (ใหม่) → bat ที่รันซ้ำ exit 0 ทันที ไม่สร้าง gateway ตัวที่ 2
  3. `gateway-watch.ps1` — เพิ่ม **proxy self-heal ทุก 2 นาที** (ตรวจ port 8899 → start ใหม่ ถ้าตาย) — กัน proxy ตายตอน gateway ยังปกติ
  4. `telegram-ipv4-proxy.py` — เพิ่ม probe ก่อน bind (กัน 2 proxy ซ้อนจาก SO_REUSEADDR)
- **บทเรียน:** ⚠️ kill แบบ `taskkill /F` ต้องลบ `gateway.lock` + `kanban/.dispatcher.lock` ค้างด้วย (ไม่งั้นตัวใหม่ค้างเงียบ); ระบบนี้มี **3 กลไกกู้คืนที่ต้องสอดคล้องกัน** (bat watchdog + gateway-watch + task) — แก้จุดเดียวไม่พอ ต้องกันทั้ง proxy ตาย + double gateway + lock ค้าง
- **ทดสอบ self-heal จริงแล้ว:** kill proxy → watcher start กลับเอง (`gateway-watch.log: PROXY: port 8899 ตาย -> เริ่มใหม่`) ✅; รัน bat ซ้ำตอน gateway ยังรัน → exit 0 ไม่ double ✅; หลัง restart ครบ: `Connected to Telegram` + heartbeat สด + proxy 1 ตัว ✅

### v6 — 15 ส.ค. 2026 (วิดีโอรีวิวตัวแรกผ่าน bot + บทเรียน 3 ข้อ)

- **วิดีโอรีวิวสินค้าตัวแรกสร้างสำเร็จผ่าน Telegram (ฟรี 100%):** สั่ง "สร้างวิดีโอโปรโมตสั้นๆ ของหูฟังบลูทูธ" → bot รัน skill `ai-factory` → `factory_manager create/build` → `scripts/script.txt` (จริง) → `video_builder.py` → `videos/promo.mp4` (1280×720, 20 วิ, h264+aac, ใช้รูปจริง 2 ใบ + Ken Burns + พากย์ไทย `th-TH-PremwadeeNeural`) — ไม่ใช้ API key สักตัว (ffmpeg + edge-tts)
- **บทเรียน ① Skill frontmatter YAML:** description ที่มี `:` (colon+space) กลางประโยค (เช่น "...short videos: build them...") ทำให้ YAML parse ล้ม → fallback → `platforms` กลายเป็น string `'[windows]'` → `skill_matches_platform` ไม่ match → **skill ถูกซ่อนจาก system prompt เงียบๆ** (snapshot เก็บ `description: ""`). **ทางแก้:** ครอบ description ด้วย double-quotes เสมอ; ตรวจด้วย `parse_frontmatter` + ดู snapshot (`grep description .skills_prompt_snapshot.json`)
- **บทเรียน ② Skill cache 2 ชั้น:** แก้ SKILL.md แล้ว bot ยังไม่เห็น — (1) gateway มี **in-process LRU cache** (ต้อง restart gateway) + (2) **session เก่าเก็บ system prompt เดิมไว้ใน state.db** (restart ก็ไม่ช่วย — ต้องพิมพ์ `/new` ใน Telegram เพื่อสร้าง session ใหม่ → rebuild system prompt + snapshot) — ลำดับ: แก้ไฟล์ → restart gateway (task) → `/new` → snapshot mtime เปลี่ยน + `description` เต็ม → ถึงจะโหลด skill ใหม่
- **บทเรียน ③ edge-tts ล้มชั่วคราว (NoAudioReceived):** network ฝั่ง Microsoft TTS หลุดๆ (เดียวกับ Telegram) — `video_builder` ตกเป็น `voiceover: skipped` แต่ video ยังสร้างได้ (ไม่มีเสียง) — **ทางแก้:** retry (CLI ตรง 5/5 ผ่าน) แล้ว rebuild — วิดีโอที่ bot สร้างรอบแรกไม่มีเสียง ต้อง rebuild ทับให้ได้เสียงครบ
- **วิธีสั่ง bot ให้ได้ผลชัวร์:** หลังแก้ skill/ระบบ ควร `/stop` → `/new` → สั่งใหม่ (session เก่าอาจค้าง auto-resume) — `/sethome` ไม่เกี่ยวกับเรื่องนี้ (ใช้ตั้ง home channel สำหรับ cron)

### v5 — 15 ส.ค. 2026 (orchestration chain 14 ระดับ)

- **Hermes = agent orchestration:** primary เปลี่ยนจาก Lightning → **Nemotron 3 Ultra** (550B, 1M ctx — จุดเด่น: agent orchestration); chain ขยายเป็น **primary + 13 fallback** จาก OpenRouter free list: lightning → laguna-s-2.1 (agentic coding) → super-120b (MTP/accuracy) → north-mini-code (JSON tool use) → gpt-oss-20b (function calling) → nano-omni (multimodal) → gemma-4-26b (function calling) → Nous ×3 → gemini → LM Studio เครื่องทำงาน → LM Studio เครื่องนี้
- **ทดสอบโมเดลใหม่จริงผ่าน OpenRouter API:** laguna / super / cohere / gpt-oss / nano-omni / gemma — ตอบได้ครบ (gemma เจอ 429 ชั่วคราว → retry ผ่าน)
- **ระบบ self-heal พิสูจน์จริง:** network ไป Telegram หลุด ~2 นาที → gateway retry + reconnect ผ่าน proxy เอง (ไม่มี watchdog ฆ่า)
- **docs ซิงก์ chain ใหม่:** README · Quick-Start · FALLBACK-AI-SETUP · Workthrough + copy ใน hermes-shared (push แล้ว)

### v4 — 15 ส.ค. 2026 (reorder chain + fix Telegram proxy)

- **Reorder fallback chain:** primary เปลี่ยนจาก Gemini → **OpenRouter `nvidia/nemotron-3.5-lightning:free`** (1M ctx, reasoning — รุ่นใหม่สุด; ทดสอบจริงผ่าน Telegram API 13.1s) → `nemotron-3-ultra-550b-a55b:free` → Nous × 3 (solar-pro4 → hy3 → stepfun) → **Gemini `gemini-3.6-flash` (ชั้น ⑥)** → LM Studio เครื่องทำงาน → LM Studio เครื่องนี้
- **Fix Telegram network หลุด (IPv6 route พังของ ISP):** local IPv4 proxy `shared/tools/telegram-ipv4-proxy.py` + ตั้ง `TELEGRAM_PROXY` ใน `start_gateway.bat` (ทุก path restart ผ่าน bat) → heartbeat สม่ำเสมอ ไม่มี error หลัง fix; gateway-watch threshold 4 → 15 นาที
- **ตัวอย่างจริง §10.5 ชุดที่ 3:** turn "สวัสดี" หลัง fix — ตอบด้วย primary ใหม่ (OpenRouter lightning) ✅
- **docs ซิงก์ chain ใหม่:** README · Quick-Start · FALLBACK-AI-SETUP · Workthrough + copy ใน hermes-shared (push แล้ว)

### v3 — 14 ส.ค. 2026 (fallback chain ใหม่ + docs ซิงก์)

- **Fallback chain 5 → 8 ระดับ:** เพิ่ม **Nous Portal** (login OAuth ครั้งเดียว: `hermes auth add nous`) เป็นชั้น ②③④ — `upstage/solar-pro4:free` (524K context) → `tencent/hy3:free` (295B agentic) → `stepfun/step-3.7-flash:free` (multimodal) — ต่อจาก Gemini ก่อน OpenRouter ฟรี ×2
- **เครื่องทำงานย้าย Ollama → LM Studio:** `qwen3:8b` @ `100.77.88.33:11434` → `qwen/qwen3.5-9b` @ `100.77.88.33:1234` (entry `custom_providers` = `lmstudio-work`; ทดสอบจริงตอบ ~28s ผ่าน Tailscale)
- **สคริปต์ auto-start ฝั่งเครื่องทำงาน:** `shared/tools/work-lmstudio-autostart.ps1` — โหลด qwen3.5-9b + เปิด server (bind 0.0.0.0) อัตโนมัติตอน login
- **ทดสอบ fallback จริงผ่าน Telegram:** บังคับ Gemini ล้ม (ลบ key ชั่วคราว) → bot ตอบด้วย `solar-pro4:free` (Nous) ใน ~9.6s ✅
- **หัวข้อใหม่ §10.5:** วิธีเช็คว่า bot ตอบผ่านชั้นไหน (ดู `turn:` / `API call #1:` / `Fallback activated` / grep `100.77.88.33:1234`)
- **docs ซิงก์ config จริง:** README.md · Quick-Start.md · FALLBACK-AI-SETUP.md ตรงกับ `config.yaml` (chain 7 ชั้น + Gemini primary); `hermes fallback list` ยืนยันแล้ว
- **บทเรียน:** ⚠️ อย่าใช้ `--provider custom` ในการทดสอบ (resolve ไป OpenRouter) — ใช้ `--provider nous -m <รุ่น:free>` หรือ `--provider lmstudio-work -m qwen/qwen3.5-9b` แทน
- **Nous ใช้ได้เฉพาะโมเดล `:free`** — ตัวเสียเงิน (เช่น `anthropic/claude-sonnet-4.6`) error `requires credits` จนกว่าจะเติมเครดิตที่ portal.nousresearch.com

### v2 — 11 ส.ค. 2026

- Workflow 2 เฟส (build → review → publish), publish แยกแพลตฟอร์ม, ปุ่มยืนยัน review/โพสต์, Gateway auto-restart 2 ชั้น

---

*เอกสารนี้สร้างจากข้อมูลจริงในโปรเจกต์ (config, workflows, factory_manager.py, SKILL.md, logs) ณ วันที่ 15 สิงหาคม 2026*
