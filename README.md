# hermes-shared — ของแชร์ระหว่างเครื่องทำงาน ↔ เครื่องบ้าน

Repo นี้เก็บสิ่งที่ **ต้องแชร์** ระหว่างเครื่องทำงาน (office) กับเครื่องที่บ้าน — สกิลที่สร้างเอง + สคริปต์ + เอกสาร
**ไม่เก็บ**: `.env`, `auth.json`, `config.yaml` (มี secret/token ต่อเครื่อง), log, state.db — อย่า push เข้ามาเด็ดขาด

## โครงสร้าง

```
hermes-shared/
├── skills/                          # สกิล local (สร้างเอง — builtin 68 ตัวมีครบอยู่แล้ว ไม่ต้องแชร์)
│   ├── windows-service-management/SKILL.md
│   └── productivity/hermes-workspace-setup/SKILL.md
├── scripts/                         # สคริปต์ ops (watchdog, health-check, ฯลฯ)
│   ├── gateway-watch.ps1            #   watchdog gateway (HermesGatewayWatch + HermesGatewayLogonKick)
│   ├── lmstudio-watch.ps1           #   watchdog LM Studio (LMStudioWatch)
│   ├── lmstudio-start.ps1           #   autostart LM Studio headless
│   ├── health-check.ps1             #   ตรวจสุขภาพทุก 30 นาที → แจ้ง Telegram
│   ├── fallback-watch.ps1           #   แจ้งเตือนเมื่อ fallback เปลี่ยนชั้น
│   ├── home-use-work-local.ps1      #   เครื่องบ้าน: ชี้ local fallback ไป LM Studio เครื่องทำงาน
│   ├── setup-home-machine.ps1       #   เครื่องบ้าน: ตั้งครบชุด (Nous + LM Studio port)
│   ├── hidden-runner.vbs            #   รัน .ps1 แบบไร้หน้าต่าง (กัน terminal เด้ง)
│   └── install-*.ps1                #   ลง task scheduler
└── docs/
    ├── workthrough.md               # คู่มือแก้ปัญหาครบ (ภาษาไทย)
    ├── README.md                    # README หลักของเครื่องทำงาน
    └── home-machine-guide.md        # คู่มือ 3 ขั้นตอนสำหรับเครื่องบ้าน
```

## วิธี sync ระหว่าง 2 เครื่อง (หลังแก้ไขอะไรแล้ว)

> หลักการ: **เครื่องทำงาน = ต้นทาง** — แก้ของที่ `C:\AI Factory` แล้ว copy เข้า repo + commit + push → เครื่องบ้าน pull

### บนเครื่องทำงาน (office)
```powershell
# 1) copy ไฟล์ที่แก้ล่าสุดเข้า repo (ใช้สคริปต์ refresh ด้านล่าง หรือ copy เอง)
# 2) commit + push
cd C:\Users\suras\hermes-shared
git add -A
git commit -m "ปรับ X"
git push
```

### บนเครื่องที่บ้าน
```powershell
cd C:\Users\suras\hermes-shared
git pull
```

### สคริปต์ refresh (copy ของใหม่จาก C:\AI Factory เข้า repo — รันที่เครื่องทำงาน)
สร้าง `refresh.ps1` ข้าง repo นี้ (หรือรันคำสั่ง):
```powershell
$src = 'C:\AI Factory'
$dst = 'C:\Users\suras\hermes-shared'
Copy-Item "$src\skills\windows-service-management" "$dst\skills\" -Recurse -Force
Copy-Item "$src\skills\productivity\hermes-workspace-setup" "$dst\skills\productivity\" -Recurse -Force
Copy-Item "$src\health-check.ps1","$src\fallback-watch.ps1","$src\gateway-watch.ps1","$src\lmstudio-watch.ps1","$src\lmstudio-start.ps1","$src\hidden-runner.vbs","$src\home-use-work-local.ps1","$src\setup-home-machine.ps1","$src\install-healthcheck-task.ps1","$src\install-fallbackwatch-task.ps1" "$dst\scripts\" -Force
Copy-Item "$src\workthrough.md","$src\README.md","$src\home-machine-guide.md" "$dst\docs\" -Force
Write-Host 'refresh เสร็จ — อย่าลืม git add -A && git commit && git push'
```

## ⚠️ ข้อควรระวัง
- **ห้าม** commit: `.env`, `auth.json`, `config.yaml`, `state.db`, `kanban.db`, `logs/`, `cache/`, `sessions/`, `memories/` — มี secret/ข้อมูลต่อเครื่อง
- สกิล builtin (68 ตัว) ไม่ต้องแชร์ — อัปเดต `hermes` ให้ version ตรงกันทั้ง 2 เครื่องก็พอ
- หลัง pull สกิลที่เครื่องบ้าน: ตรวจว่า Hermes เห็นด้วย `hermes skills list` (ควรเห็นเป็น `local` source)
