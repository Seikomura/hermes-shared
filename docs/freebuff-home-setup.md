# คู่มือตั้งค่า Hermes agent ที่เครื่องบ้าน — สำหรับ Freebuff เครื่องบ้าน

> ไฟล์นี้เขียนขึ้นเพื่อให้ **Freebuff ที่เครื่องบ้าน** อ่านแล้วตั้งค่า Hermes agent ที่เครื่องบ้านให้ถูกต้อง
> อ่านให้จบก่อนเริ่มลงมือ — อย่าข้ามขั้นตอน

---

## 1. บริบท: ระบบ 2 เครื่อง

| | เครื่องทำงาน (office) | เครื่องบ้าน (home) |
|---|---|---|
| บทบาท | **เครื่องหลัก** — bot หลัก + local AI (LM Studio) + ระบบครบ | **เครื่องสำรอง** — สเปคต่ำ ลง LM Studio ไม่ไหว |
| Local AI | LM Studio บนเครื่องนี้ (`qwen/qwen3.5-9b`, port 1234, bind 0.0.0.0) | **ไม่มี** — ใช้ local AI ของเครื่องทำงานผ่าน Tailscale (`100.77.88.33:1234`) |
| Telegram | บัญชีเดียวกัน · **bot คนละตัว** (token ต่างกัน อยู่ใน `.env` ของแต่ละเครื่อง) | บัญชีเดียวกัน · **bot คนละตัว** (token ต่างกัน) |
| HERMES_HOME | `C:\AI Factory` | `C:\AI Factory` (ค่า default เดียวกัน) |

**สิ่งที่แชร์ระหว่าง 2 เครื่อง = ผ่าน repo นี้ (hermes-shared) เท่านั้น**
**สิ่งที่ไม่แชร์ = `.env`, `auth.json`, `config.yaml`** (มี secret/token ต่อเครื่อง — ห้ามแตะ ห้าม push)

---

## 2. หลักการ: repo นี้คือ CENTER ของสกิล + สคริปต์ + เอกสาร

```
repo (GitHub) = ต้นทาง
   ▲              │
   │ push         │ pull + deploy (sync.ps1)
   │              ▼
เครื่องทำงาน ◄──────► เครื่องบ้าน
```

- **สกิล local** (สร้างเอง 2 ตัว: `windows-service-management`, `hermes-workspace-setup`) — ต้นทางอยู่ที่ `repo\skills\`
- **สคริปต์ ops** (watchdog, health-check, fallback-watch, ฯลฯ) — อยู่ที่ `repo\scripts\`
- **เอกสาร** — อยู่ที่ `repo\docs\` (รวมไฟล์นี้)

### ⚠️ กฎเหล็ก (ห้ามละเมิด)
1. **แก้สกิลที่ repo เท่านั้น** (`C:\Users\suras\hermes-shared\skills\...`) — ห้ามแก้ที่ `C:\AI Factory\skills\` ตรงๆ
   - เผลอแก้ที่เครื่อง? → กู้กลับ: `powershell -ExecutionPolicy Bypass -File sync.ps1 -Import` (เอากลับเข้า repo) แล้ว commit+push
2. **ห้าม push** `.env`, `auth.json`, `config.yaml`, log, db — มี `.gitignore` + pre-commit hook กันอยู่ แต่ห้ามพยายามเลี่ยง
3. **อย่าแก้ `config.yaml` เครื่องบ้านโดยไม่สำรอง** — สคริปต์ที่แชร์มาจะสำรองให้อัตโนมัติทุกครั้ง

---

## 3. ขั้นตอนติดตั้งครั้งแรก (เครื่องบ้าน)

> ต้องมี: git + อินเทอร์เน็ต + login GitHub (บัญชีเดียวกับเครื่องทำงาน)

```powershell
# 1) เช็ค HERMES_HOME (ถ้า config.yaml อยู่ที่อื่น ใช้ path นั้นแทน C:\AI Factory)
echo $env:HERMES_HOME

# 2) clone repo (จะเด้งหน้าต่าง login GitHub)
cd C:\Users\suras
git clone https://github.com/Seikomura/hermes-shared.git

# 3) ติดตั้ง pre-commit hook (กัน secret หลุด)
cd C:\Users\suras\hermes-shared
Copy-Item check-secrets.ps1 .git\hooks\pre-commit

# 4) ลงทุกอย่าง: สกิล + สคริปต์ + Task Scheduler (คำสั่งเดียวจบ)
powershell -ExecutionPolicy Bypass -File sync.ps1 -Scripts
```

**หมายเหตุ:** ถ้าเครื่องบ้านยังไม่เคยลง Hermes agent เลย (ไม่มี gateway/config) — ต้องติดตั้งตัว Hermes agent ก่อน (เหมือนที่ลงที่เครื่องทำงาน) แล้วค่อยทำขั้นตอนบน — task `HermesGateway` ที่ `install-tasks.ps1` ตรวจ ต้องมีอยู่ถึงจะ restart ผ่านได้

---

## 4. ตรวจสอบว่าสำเร็จ

```powershell
# 1) สกิลเห็นครบ (ควรเห็น 2 ตัวเป็น local / enabled)
hermes skills list

# 2) task ครบชุด (ควรเห็น Ready 4 ตัว + ข้าม LMStudioWatch เพราะเครื่องนี้ไม่มี LM Studio)
schtasks /query /tn HermesGatewayWatch
schtasks /query /tn HermesGatewayLogonKick
schtasks /query /tn HermesHealthCheck
schtasks /query /tn HermesFallbackWatch

# 3) ลองคุยกับ bot ผ่าน Telegram → ควรตอบกลับภายใน ~1 นาที
```

---

## 5. งานประจำ (เครื่องบ้าน)

### รับของใหม่จากเครื่องทำงาน (เมื่อเครื่องทำงาน push สกิล/สคริปต์ใหม่)
```powershell
cd C:\Users\suras\hermes-shared
powershell -ExecutionPolicy Bypass -File sync.ps1 -Scripts
```

### ให้ bot เครื่องบ้านใช้ local AI ของเครื่องทำงาน (fallback สุดท้าย)
```powershell
# เครื่องทำงานต้องเปิดค้างไว้ + LM Studio รันอยู่ก่อน (curl http://100.77.88.33:1234/v1/models ต้องตอบ)
powershell -ExecutionPolicy Bypass -File C:\AI Factory\home-use-work-local.ps1
# ทดสอบ: curl http://100.77.88.33:1234/v1/models  → เห็น qwen/qwen3.5-9b = พร้อมใช้
```
> สคริปต์นี้แก้**เฉพาะชั้น local fallback** ใน config.yaml (สำรองให้อัตโนมัติ) — ไม่แตะ provider อื่น รายละเอียดใน `docs\home-machine-guide.md`

---

## 6. แก้ปัญหาเบื้องต้น (ก่อนโทรหาเครื่องทำงาน)

| อาการ | ตรวจอะไร | ทำยังไง |
|---|---|---|
| Bot เงียบ / ไม่ตอบ | `C:\AI Factory\state\gateway.heartbeat` (อายุเกิน 4 นาที = ตาย) | รอ ~2-4 นาที — `HermesGatewayWatch` จะ restart ให้เอง ตรวจ `logs\gateway-watch.log` |
| ยังเงียบเกิน 10 นาที | `logs\gateway.log`, `logs\errors.log` | restart เอง: `schtasks /end /TN HermesGateway; schtasks /run /TN HermesGateway` |
| fallback หลุดถึงชั้นที่ไม่ควร | `logs\agent.log` (มี fallback-watch แจ้ง Telegram อยู่แล้ว) | ดู chain: `hermes fallback list` |
| เชื่อม local เครื่องทำงานไม่ได้ | `curl http://100.77.88.33:1234/v1/models` | เครื่องทำงานอาจปิด/ LM Studio หลุด — ตรวจ Tailscale: `tailscale status` |

**คู่มือแก้ปัญหาครบถ้วน: `docs\workthrough.md`** — อ่านก่อนถามเครื่องทำงาน

---

## 7. สรุปสิ่งที่ Freebuff เครื่องบ้านต้องจำ

1. **repo นี้ = center** — ของใหม่ทั้งหมดมาจาก `git pull` + `sync.ps1`
2. **สกิลแก้ที่ repo** ไม่ใช่ที่ `C:\AI Factory\skills\` ตรงๆ
3. **ห้ามแตะ/ห้าม push** secret (`.env`, `auth.json`, `config.yaml`)
4. เครื่องบ้าน **ไม่มี LM Studio** — ใช้ของเครื่องทำงานผ่าน Tailscale (`home-use-work-local.ps1`)
5. ปัญหาส่วนใหญ่ **watchdog แก้ให้เอง** — รอ 2-4 นาทีก่อน ดู log แล้วค่อยลงมือ
