# คู่มือย่อ: ตั้งเครื่องที่บ้านใช้ Local AI ของเครื่องทำงาน (ผ่าน Tailscale)

> เป้าหมาย: ให้ bot ที่เครื่องบ้านใช้ **qwen3.5-9b ของเครื่องทำงาน** เป็น fallback สุดท้าย
> (เครื่องบ้านเสปคต่ำ — ไม่ต้องรันโมเดลเอง แค่ชี้ไปเครื่องทำงาน)

---

## ✅ ก่อนเริ่ม (เช็ค 2 อย่าง)
- [ ] **เครื่องทำงาน** เปิดค้างไว้ + LM Studio รันอยู่ (ตรวจได้: `curl http://100.77.88.33:1234/v1/models`)
- [ ] **เครื่องบ้าน** เปิด + Tailscale ออนไลน์ (ไอคอนถาดระบบเป็นสีเขียว)

---

## ขั้นตอนที่ 1: รันสคริปต์

1. คัดลอกไฟล์ `home-use-work-local.ps1` ไปเครื่องบ้าน
2. เปิด PowerShell ที่เครื่องบ้าน แล้วรัน:

```powershell
powershell -ExecutionPolicy Bypass -File home-use-work-local.ps1
```

- config อยู่ที่อื่น: `-HERMES_HOME 'C:\เส้นทาง\ของคุณ'`
- IP เครื่องทำงานต่าง: `-WorkIP 'IP'`
- ไม่ต้องการ restart อัตโนมัติ: `-SkipRestart`

สคริปต์จะ: **สำรอง config** → เปลี่ยน entry local ให้ชี้เครื่องทำงาน (`100.77.88.33:1234`) + โมเดล `qwen/qwen3.5-9b` → restart gateway
→ **ไม่แตะ** provider อื่น (Nous/Gemini/OpenRouter), `.env`, `auth.json`

## ขั้นตอนที่ 2: ทดสอบเชื่อมต่อ

```powershell
curl http://100.77.88.33:1234/v1/models
```

- ✅ เห็น `qwen/qwen3.5-9b` = เชื่อมต่อถึงเครื่องทำงานแล้ว
- ❌ ไม่ติด → ดูหัวข้อ "แก้ปัญหา" ด้านล่าง

ตรวจ chain fallback (ควรเห็น local เป็นชั้นสุดท้าย):

```powershell
hermes fallback list
```

## ขั้นตอนที่ 3: ลองคุยกับ bot

1. รอ ~1 นาที (gateway restart + โมเดลโหลด)
2. ส่งข้อความปกติใน Telegram
3. **ทดสอบ fallback จริง** (เผื่อชั้นหลักยังทำงานอยู่ จะไม่ได้เห็น local): ปิดเน็ต/API ที่เครื่องบ้าน หรือถามคำถามที่บังคับ fallback — ถ้าอยากรู้ว่าตอบผ่าน local จริงไหม ดู log:

```powershell
Get-Content "C:\AI Factory\logs\agent.log" -Tail 30 | Select-String "provider=custom"
```

---

## 🔧 แก้ปัญหา

| อาการ | สาเหตุ/วิธีแก้ |
|---|---|
| `curl` ไม่ติด | เครื่องทำงานปิดอยู่ หรือ LM Studio ไม่รัน → เปิดเครื่องทำงาน/เช็ค LM Studio Watchdog |
| bot ตอบช้าแวบแรก | รอโมเดลโหลด ~20-30 วิ (ครั้งแรกหลัง boot) |
| ตอบไม่ได้เลย | รัน `hermes fallback list` + `hermes chat -q "ตอบว่า OK" -Q --provider custom -m qwen/qwen3.5-9b --max-turns 2` ดู error |
| อยากคืนค่าเดิม | มี backup อัตโนมัติ: `config.yaml.bak-local-<เวลา>` — คัดลอกกลับแล้ว restart |

## ⚠️ สำคัญ
- เครื่องทำงาน**ต้องเปิดค้างไว้**ตลอด — ไม่งั้นชั้น local ของเครื่องบ้านใช้ไม่ได้ (ชั้น cloud ยังทำงาน)
- ถ้าอยากเลิกใช้: ลบ entry `custom` ใน config.yaml แล้ว restart (หรือใช้ไฟล์ backup)
