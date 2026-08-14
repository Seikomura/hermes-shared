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
│   ├── home-use-work-local.ps1     #   เครื่องบ้าน: ชี้ local fallback ไป LM Studio เครื่องทำงาน
│   ├── setup-home-machine.ps1      #   เครื่องบ้าน: ตั้งครบชุด (Nous + LM Studio port)
│   ├── hidden-runner.vbs           #   รัน .ps1 แบบไร้หน้าต่าง (กัน terminal เด้ง)
│   ├── check-secrets.ps1           #   สแกน secret ก่อน commit (กัน key หลุด)
│   └── install-*.ps1               #   (ตัวเก่า) ลง task ทีละตัว
└── docs/
    ├── workthrough.md              # คู่มือแก้ปัญหาครบ (ภาษาไทย)
    ├── README.md                   # README หลักของเครื่องทำงาน
    ├── home-machine-guide.md       # คู่มือ 3 ขั้นตอนสำหรับเครื่องบ้าน (รันสคริปต์ + ทดสอบ + คุย bot)
    └── freebuff-home-setup.md      # ⭐ คู่มือตั้งค่าเครื่องบ้าน — ให้ Freebuff เครื่องบ้านอ่านก่อนลงมือ
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
