# hermes-shared — ศูนย์กลางอัปเดตสกิลระหว่างเครื่องทำงาน ↔ เครื่องบ้าน

Repo นี้คือ **CENTER (source of truth)** สำหรับของที่แชร์ระหว่าง 2 เครื่อง: สกิล local ที่สร้างเอง + สคริปต์ + เอกสาร
**ไม่เก็บ**: `.env`, `auth.json`, `config.yaml` (มี secret/token ต่อเครื่อง), log, state.db — อย่า push เข้ามาเด็ดขาด

## หลักการทำงาน (สำคัญ)

```
repo (GitHub) = ต้นทาง
   ▲              │
   │ push         │ pull + deploy (sync.ps1)
   │              ▼
เครื่องทำงาน ◄──────► เครื่องบ้าน  (ทั้งคู่รัน sync.ps1)
```

- **แก้สกิลที่ repo** (`C:\Users\suras\hermes-shared\skills\...`) — ไม่แก้ที่ `C:\AI Factory\skills\` ตรงๆ
- **เครื่องทำงาน:** แก้ที่ repo → รัน `sync.ps1` (ลงเครื่องนี้ให้เห็นผล) → `git commit` + `git push`
- **เครื่องบ้าน:** รัน `sync.ps1` (pull + ลงเครื่องเองให้อัตโนมัติ)
- เผลอแก้ที่ `C:\AI Factory\skills\` ตรงๆ? ใช้ `sync.ps1 -Import` เอากลับเข้า repo ได้

## โครงสร้าง

```
hermes-shared/
├── sync.ps1                        # ⭐ คำสั่งเดียว sync 2 เครื่อง (pull + deploy สกิล + สคริปต์ + tasks)
├── config.orchestration.example.yaml  # ⭐ template fallback chain orchestration (14 ระดับ) — คัดลอกไป config.yaml (ไม่มี secret)
├── skills/                         # สกิล local (builtin 68 ตัวมีครบอยู่แล้ว ไม่ต้องแชร์)
│   ├── windows-service-management/SKILL.md
│   └── productivity/hermes-workspace-setup/SKILL.md
├── scripts/                        # สคริปต์ ops (ลงเครื่องด้วย -Scripts)
│   ├── install-tasks.ps1           #   ⭐ ลง Task Scheduler ทั้งชุด (idempotent — ข้ามตัวที่มีอยู่)
│   ├── gateway-watch.ps1           #   watchdog gateway (HermesGatewayWatch + HermesGatewayLogonKick)
│   ├── lmstudio-watch.ps1          #   watchdog LM Studio (LMStudioWatch — ลงเฉพาะเครื่องที่มี LM Studio)
│   ├── lmstudio-start.ps1          #   autostart LM Studio headless
│   ├── health-check.ps1            #   ตรวจสุขภาพทุก 30 นาที → แจ้ง Telegram
│   ├── fallback-watch.ps1          #   แจ้งเตือนเมื่อ fallback เปลี่ยนชั้น
│   ├── model-health-check.py       #   ตรวจโมเดล orchestration 8 ตัว (availability + latency)
│   ├── home-use-work-local.ps1     #   เครื่องบ้าน: ชี้ local fallback ไป LM Studio เครื่องทำงาน
│   ├── setup-home-machine.ps1      #   เครื่องบ้าน: ตั้งครบชุด (Nous + LM Studio port)
│   ├── hidden-runner.vbs           #   รัน .ps1 แบบไร้หน้าต่าง (กัน terminal เด้ง)
│   ├── check-secrets.ps1           #   สแกน secret ก่อน commit (กัน key หลุด)
│   └── install-*.ps1               #   (ตัวเก่า) ลง task ทีละตัว
│   # ── เพิ่มจากเครื่องบ้าน (ระบบ gateway แบบ bat-watchdog + autostart ฝั่งเครื่องทำงาน) ──
│   ├── start_gateway.bat           #   ตัวหลัก: watchdog loop รัน hermes gateway (restart อัตโนมัติเมื่อ crash)
│   ├── stop_gateway.bat            #   หยุด gateway แบบสะอาด (ไม่ให้ watchdog ขึ้นใหม่)
│   ├── start_gateway_hidden.vbs    #   wrapper รัน start_gateway.bat แบบไร้หน้าต่าง
│   ├── register_gateway_task.ps1   #   ลง task AI_Factory_Gateway (เปิดตอน login)
│   └── watchdog_notify.py          #   แจ้ง Telegram ทุกครั้งที่ gateway ตาย (อ่าน token จาก .env)
└── docs/
    ├── workthrough.md              # คู่มือแก้ปัญหาครบ (ภาษาไทย) — จากเครื่องทำงาน
    ├── README.md                   # README หลักของเครื่องทำงาน
    # ── เพิ่มจากเครื่องบ้าน (AI Factory manual + fallback chain ล่าสุด — API-only 12 ชั้น) ──
    ├── ai-factory-workthrough.md   # คู่มือ AI Factory (มี §10.5 วิธีเช็คว่า bot ตอบผ่านชั้นไหน + §14 Changelog)
    ├── ai-factory-readme.md        # README ของ AI Factory (fallback chain 7 ชั้น + Nous free models)
    ├── ai-factory-quick-start.md   # Quick-Start ของ AI Factory
    ├── fallback-ai-setup.md        # สรุป config ไฟนอล + คำสั่งเช็คสถานะ fallback
    └── system-overview.md          # ⭐ ภาพรวมระบบ 1 ไฟล์ (สถาปัตยกรรม/scripts/tasks/status) — ใช้แชร์ทีม
```

## วิธีใช้ sync.ps1 (ทั้ง 2 เครื่องใช้คำสั่งเดียวกัน)

```powershell
powershell -ExecutionPolicy Bypass -File sync.ps1            # pull ล่าสุด + ลงสกิล
powershell -ExecutionPolicy Bypass -File sync.ps1 -Scripts   # + ลงสคริปต์ ops และลง Task Scheduler อัตโนมัติ
```

| Flag | ความหมาย |
|---|---|
| `-SkipPull` | ข้าม `git pull` (offline / เพิ่ง push เอง) |
| `-Scripts` | ลงสคริปต์ใน `scripts\` ไปที่ `HERMES_HOME` + **รัน `install-tasks.ps1` ลง Task Scheduler** (watchdog/health-check/fallback — ข้ามตัวที่มีอยู่แล้ว, ข้าม LMStudioWatch ถ้าเครื่องไม่มี LM Studio) |
| `-Import` | **ฉุกเฉิน** — เอา�สกิลที่แก้มือที่ `HERMES_HOME\skills\` กลับเข้า repo (แล้ว commit+push เอง) |
| `-HERMES_HOME 'C:\...'` | ถ้าเครื่องนี้เก็บ config ที่อื่น (default: `C:\AI Factory`) |

> สคริปต์จะ copy แบบ **merge** — ลง/ทับเฉพาะสกิลใน repo ไม่ลบสกิล builtin หรือสกิลอื่นในเครื่อง
> log การทำงาน: `sync.log` (อยู่ข้าง sync.ps1)
> หมายเหตุ: `install-tasks.ps1` ใช้ได้กับ PS 5.1+ — ถ้าต้องการลง task ทีละตัวใช้ `install-healthcheck-task.ps1` / `install-fallbackwatch-task.ps1` เดิมได้
> ⚠️ **สคริปต์มี 2 ระบบดูแล gateway ให้เลือกใช้ (อย่าใช้พร้อมกัน 2 ตัว):**
> 1) **แบบ bat-watchdog** (`start_gateway.bat` + task `AI_Factory_Gateway`) — เครื่องบ้านใช้อยู่: restart เมื่อ process ตาย
> 2) **แบบ heartbeat** (`gateway-watch.ps1` + task `HermesGatewayWatch`) — เครื่องทำงานใช้อยู่: restart เมื่อ heartbeat ค้าง (ทุก 2 นาที)
> แต่ละเครื่องเลือกแบบเดียวเพื่อกันการ restart ซ้ำซ้อน

## วิธี sync จริง (ขั้นตอนปกติ)

### เครื่องทำงาน (office) — แก้สกิล + เผยแพร่
```powershell
# 1) แก้สกิลที่:  C:\Users\suras\hermes-shared\skills\...
# 2) ลงเครื่องนี้ให้เห็นผล (ทดสอบก่อน push ได้)
cd C:\Users\suras\hermes-shared
powershell -ExecutionPolicy Bypass -File sync.ps1 -SkipPull
hermes skills list          # ตรวจว่าสกิลใหม่ขึ้นแล้ว
# 3) เผยแพร่
git add -A
git commit -m "ปรับสกิล X"
git push
```

### เครื่องที่บ้าน — รับของใหม่ (คำสั่งเดียวครบ: pull + สกิล + สคริปต์ + tasks)
```powershell
cd C:\Users\suras\hermes-shared
powershell -ExecutionPolicy Bypass -File sync.ps1 -Scripts     # pull + ลงสกิล + สคริปต์ + ลง Task Scheduler
hermes skills list                                             # ตรวจว่าสกิลใหม่ขึ้นแล้ว
schtasks /query /tn HermesGatewayWatch                         # ตรวจว่า watchdog ลงแล้ว
```

### ครั้งแรกที่เครื่องบ้าน (ติดตั้งครั้งเดียว)
```powershell
# 1) clone (จะเด้งหน้าต่าง login GitHub — ใช้บัญชีเดียวกันกับเครื่องทำงาน)
cd C:\Users\suras
git clone https://github.com/Seikomura/hermes-shared.git

# 2) ติดตั้ง pre-commit hook (กัน secret หลุด — ต้องทำเหมือนเครื่องทำงาน)
cd hermes-shared
Copy-Item check-secrets.ps1 .git\hooks\pre-commit

# 3) ลงสกิล + สคริปต์ + Task Scheduler ชุดเดียวกับเครื่องทำงาน (คำสั่งเดียวจบ)
powershell -ExecutionPolicy Bypass -File sync.ps1 -Scripts
hermes skills list
```

## 🎯 Fallback chain orchestration (14 ระดับ) — แชร์จากเครื่องบ้าน (15 ส.ค. 2026)

Hermes ตั้งเป็น **agent orchestration**: primary = **Nemotron 3 Ultra** (`nvidia/nemotron-3-ultra-550b-a55b:free` — จุดเด่น: agent orchestration) + fallback 13 ชั้น:

| # | โมเดล | บทบาท |
|---|---|---|
| **Primary** | `nvidia/nemotron-3-ultra-550b-a55b:free` | 🎯 agent orchestration (550B, 1M ctx) |
| 1 | `nvidia/nemotron-3.5-lightning:free` | 1M ctx, reasoning, รุ่นใหม่สุด |
| 2 | `poolside/laguna-s-2.1:free` | agentic coding (Terminal-Bench 70.2%) |
| 3 | `nvidia/nemotron-3-super-120b-a12b:free` | MTP, accuracy (AIME/SWE-Bench) |
| 4 | `cohere/north-mini-code:free` | JSON schema tool use |
| 5 | `openai/gpt-oss-20b:free` | function calling, structured outputs |
| 6 | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free` | multimodal |
| 7 | `google/gemma-4-26b-a4b-it:free` | native function calling |
| 8-10 | Nous ฟรี ×3 (`upstage/solar-pro4:free` → `tencent/hy3:free` → `stepfun/step-3.7-flash:free`) | 524K / 295B / multimodal |
| 11 | `gemini-3.6-flash` (gemini) | AI Studio — ต้องมี `GEMINI_API_KEY` |
| 12-13 | LM Studio (`qwen/qwen3.5-9b` → `qwen/qwen3-1.7b`) | local สำรอง (ต่อเครื่อง) |

**เครื่องทำงานเอาไปใช้ยังไง (~1 นาที):**

```powershell
# 1) สำรอง config เดิม
copy C:\AI Factory\config.yaml C:\AI Factory\config.yaml.bak-<วันนี้>
# 2) คัดลอก template ไปทับ (ไม่มี secret — key อยู่ใน .env)
copy config.orchestration.example.yaml C:\AI Factory\config.yaml
# 3) เปิด config.yaml แล้วปรับชั้น LM Studio ท้ายสุด (⑬⑭) + custom_providers
#    ให้เป็นของเครื่องตัวเอง (เครื่องทำงาน: qwen/qwen3.5-9b @ 127.0.0.1:1234 — ดูคอมเมนต์ในไฟล์)
# 4) รีสตาร์ท gateway ผ่าน task ของเครื่อง
# 5) ตรวจ
hermes fallback list
python scripts\model-health-check.py        # ควรเห็น 8/8 OK
```

> ⚠️ template ไม่มี secret — key ทั้งหมดอยู่ใน `.env` ของแต่ละเครื่อง (ห้าม push ขึ้น git)
> 💡 ไม่อยากได้ชั้นไหน (Nous/Gemini/local) ตัดรายการใน `fallback_providers` ออกได้เลย
> 📖 รายละเอียด + ตัวอย่าง log จริง: `docs/fallback-ai-setup.md` · `docs/ai-factory-workthrough.md` (§10.5)

## 🔒 ความปลอดภัย (API key / secret)

- **มี `.gitignore` กันไว้แล้ว** — ครอบคลุม `.env*`, `auth*`, `secrets*`, `*.pem/*.key`, `config.yaml`, `*.db`, `logs/`, `cache/`, `sessions/`, `memories/` ฯลฯ
- **มี `check-secrets.ps1`** — สแกน secret pattern (Google / OpenAI / Anthropic / GitHub / Slack / AWS / JWT) ก่อน commit
- **pre-commit hook** (รันอัตโนมัติทุก commit ที่เครื่องทำงานแล้ว) — **ต้องติดตั้งที่เครื่องบ้านด้วยหลัง clone**:
  ```powershell
  Copy-Item check-secrets.ps1 .git\hooks\pre-commit
  ```
  > หมายเหตุ: hook เป็นไฟล์ shell ที่เรียก powershell — ถ้าเครื่องบ้าน copy ตรงๆ ไม่ได้ ให้รัน `powershell -ExecutionPolicy Bypass -File check-secrets.ps1` ก่อน commit เองก็ได้
- **ห้าม** commit: `.env`, `auth.json`, `config.yaml`, `state.db`, `kanban.db`, `logs/`, `cache/`, `sessions/`, `memories/` — มี secret/ข้อมูลต่อเครื่อง
- สกิล builtin (68 ตัว) ไม่ต้องแชร์ — อัปเดต `hermes` ให้ version ตรงกันทั้ง 2 เครื่องก็พอ
- หลัง sync สกิลที่เครื่องบ้าน: ตรวจว่า Hermes เห็นด้วย `hermes skills list` (ควรเห็นเป็น `local` source)
