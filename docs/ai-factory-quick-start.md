# 🚀 AI FACTORY — Quick Start (ฉบับมือใหม่)

> คู่มือสั้นๆ เริ่มใช้ระบบภายใน 5 นาที รายละเอียดเต็มดูที่ **[Workthrough.md](Workthrough.md)**

AI FACTORY คือระบบที่ใช้ AI (Hermes Agent) สร้างและจัดการสินค้าดิจิทัล เช่น **วิดีโอโปรโมตสินค้า Shopee** หรือ **E-book** โดยสินค้าแต่ละชิ้นทำงานเป็น **2 เฟส**:

```
สร้าง Product → build (gen draft) → รีวิวด้วยปุ่ม → publish (โพสต์ทีละแพลตฟอร์ม)
```

---

## ✅ สิ่งที่ต้องมีก่อนเริ่ม

- Windows + Python (ไม่ต้องติดตั้ง package เพิ่ม)
- **ffmpeg** (ฟรี) สำหรับสร้างวิดีโอ — ติดตั้ง: `winget install Gyan.FFmpeg` (ตรวจ: `ffmpeg -version`)
- **edge-tts** *(optional, ฟรี)* สำหรับเสียงพากย์ — ติดตั้ง: `pip install edge-tts` (ต้องมีอินเทอร์เน็ต)
- Hermes Agent: `C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe`
- OpenRouter API Key (สำหรับให้ AI ทำงาน)
- **Nous Portal** *(ฟรี)* สำหรับโมเดลฟรีสำรอง — login OAuth ครั้งเดียว: `hermes auth add nous` (รายละเอียด: Workthrough §4)

---

## 🛠️ ขั้นตอนที่ 1: สร้างไฟล์ .env (ทำครั้งแรกครั้งเดียว)

เปิด PowerShell แล้วคัดลอกตัวอย่างเป็นไฟล์จริง แล้ว**เปิดไฟล์แก้ไข**ใส่ key ของคุณ:

```powershell
Copy-Item C:\AI_FACTORY\shared\hermes_home\.env.example C:\AI_FACTORY\shared\hermes_home\.env
Copy-Item C:\AI_FACTORY\factories\shopee_affiliate\.env.example C:\AI_FACTORY\factories\shopee_affiliate\.env
Copy-Item C:\AI_FACTORY\factories\ebook\.env.example C:\AI_FACTORY\factories\ebook\.env
```

- ไฟล์ `shared\hermes_home\.env` → ใส่ `OPENROUTER_API_KEY` (จำเป็น), `GEMINI_API_KEY` (ถ้ามี — จะใช้ Gemini เป็น model หลัก), `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` (ถ้าจะใช้ Telegram)
- ไฟล์ `.env` ของแต่ละโรงงาน → ใส่ key เฉพาะที่จำเป็น (ขั้นแรกยังไม่ต้องก็ได้ เพราะระบบยังไม่ต่อ API จริง)

---

## ⚙️ ขั้นตอนที่ 2: ตั้งค่าเริ่มต้น (ทุกครั้งที่เปิด PowerShell ใหม่)

วาง 3 บรรทัดนี้ก่อนใช้งานทุกครั้ง:

```powershell
$env:HERMES_HOME='C:\AI_FACTORY\shared\hermes_home'
$env:AI_FACTORY_ROOT='C:\AI_FACTORY'
$hermes='C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe'
```

---

## 🧪 ขั้นตอนที่ 3: ทดสอบว่าระบบทำงาน

```powershell
python C:\AI_FACTORY\shared\tools\factory_manager.py list
```

ควรเห็น JSON แสดง Factory 2 ตัว: `shopee_affiliate` และ `ebook` ✅

---

## 🧠 AI ตอบด้วยโมเดลไหน (fallback chain)

`shared\hermes_home\config.yaml` ตั้งไว้แล้ว **8 ระดับ** — ลำดับแรกที่ใช้ได้จะถูกใช้ (เรียงตามประสิทธิภาพ ตัวดีที่สุดมาก่อน):

| # | Provider | โมเดล | หมายเหตุ |
|---|---|---|---|
| ① | **OpenRouter** (หลัก, ฟรี) | `nvidia/nemotron-3.5-lightning:free` | 1M ctx, reasoning — รุ่นใหม่สุด |
| ② | OpenRouter (ฟรี) | `nvidia/nemotron-3-ultra-550b-a55b:free` | 550B, 1M ctx |
| ③ | Nous Portal (ฟรี) | `upstage/solar-pro4:free` | 524K context — เหมาะงานยาว |
| ④ | Nous Portal (ฟรี) | `tencent/hy3:free` | 295B, agentic |
| ⑤ | Nous Portal (ฟรี) | `stepfun/step-3.7-flash:free` | multimodal |
| ⑥ | Gemini | `gemini-3.6-flash` | ใส่ `GEMINI_API_KEY` ใน .env |
| ⑦ | LM Studio เครื่องทำงาน (Tailscale) | `qwen/qwen3.5-9b` | ต้องเปิด server ที่เครื่องทำงาน (`work-lmstudio-autostart.ps1`) |
| ⑧ | LM Studio เครื่องนี้ (สำรองสุดท้าย) | `qwen/qwen3-1.7b` | เสปคต่ำ — ใช้ยามฉุกเฉินเท่านั้น |

- **Nous ใช้ได้เฉพาะโมเดล `:free`** — ตัวเสียเงิน (เช่น `anthropic/claude-sonnet-4.6`) จะ error `requires credits` จนกว่าจะเติมเครดิตที่ portal.nousresearch.com
- วิธีเช็คว่า bot ตอบผ่านโมเดลไหนจริง: Workthrough §10.4 (ดู `agent.log` grep `100.77.88.33:1234` สำหรับชั้นเครื่องทำงาน)

---

## 📦 ขั้นตอนที่ 4: สร้าง Product ชิ้นแรก

```powershell
python C:\AI_FACTORY\shared\tools\factory_manager.py create --factory shopee_affiliate --name "My Product"
```

- สร้างโฟลเดอร์สินค้าใต้ `C:\AI_FACTORY\products\My-Product\` พร้อมโฟลเดอร์ย่อยครบทุก stage
- ผลลัพธ์ JSON ขึ้น `"status": "CREATED"` = สำเร็จ
- สร้าง E-book เปลี่ยน `--factory ebook`

---

## ▶️ ขั้นตอนที่ 5: สร้าง draft (build) และรีวิว

```powershell
# 1) สร้าง draft (วิดีโอ stage ใช้ ffmpeg ฟรีที่เครื่อง — ใส่ภาพสินค้าลง products\My-Product\images\ ก่อนรัน)
python C:\AI_FACTORY\shared\tools\factory_manager.py build --factory shopee_affiliate --product "My-Product"

# 2) ตรวจสอบไฟล์ที่ gen ได้ (ควรเห็น videos/promo.mp4 ไฟล์วิดีโอจริง)
python C:\AI_FACTORY\shared\tools\factory_manager.py artifacts --product "My-Product"

# 3) รีวิว: อนุมัติ หรือส่งกลับแก้ไข
python C:\AI_FACTORY\shared\tools\factory_manager.py review --product "My-Product" --status approve
# หรือ:  python ... review --product "My-Product" --status reject --notes "แก้สคริปต์ให้สั้นลง"
```

- build สำเร็จ → `"status": "DRAFT_READY"` (build ใหม่ทุกครั้งจะรีเซ็ต review เป็น pending)
- `approve` → `"status": "APPROVED"` (สินค้าที่ยังไม่ build อนุมัติไม่ได้)

---

## 📤 ขั้นตอนที่ 6: publish — โพสต์ทีละแพลตฟอร์ม

```powershell
# โพสต์แค่ YouTube ก่อน
python C:\AI_FACTORY\shared\tools\factory_manager.py publish --factory shopee_affiliate --product "My-Product" --platform youtube

# ทีหลัง: โพสต์แพลตฟอร์มที่เหลือ (tiktok, facebook)
python C:\AI_FACTORY\shared\tools\factory_manager.py publish --factory shopee_affiliate --product "My-Product"

# ebook: publish แบบขั้นเดียว (ไม่มี --platform)
python C:\AI_FACTORY\shared\tools\factory_manager.py publish --factory ebook --product "My-Book"
```

- **Gate:** ต้องผ่านรีวิว (APPROVED) ก่อน ไม่งั้น `"ok": false` พร้อมเหตุผล
- โพสต์ซ้ำแพลตฟอร์มเดิม/แพลตฟอร์มไม่รู้จัก → ปฏิเสธ
- ดูสถานะได้: `python ... status --product "My-Product"` (มี `published[]` บอกว่าโพสต์ที่ไหนไปแล้ว)

---

## 💬 ขั้นตอนที่ 7 (ไม่บังคับ): ใช้งานผ่าน Telegram พร้อมปุ่มกด

1. เปิด Gateway ค้างไว้ในหน้าต่าง PowerShell:
   ```powershell
   & $hermes gateway
   ```
2. รอเห็นข้อความ `telegram connected` (เช็คได้ที่ `shared\hermes_home\logs\gateway.log`)
3. ส่ง private message ไปที่ bot:
   ```
   /ai-factory หาสินค้า Shopee คอมมิชชันดี ขายดี หน่อย
   /ai-factory สร้าง Product Shopee ชื่อ หูฟังบลูทูธ
   ```
   > คำสั่งแรก: ค้นสินค้า Shopee ที่มี extra commission + ความนิยมสูง แล้วเลือกมาสร้าง Product (ต้องตั้งค่า Shopee API keys ก่อน) — bot จะโชว์ shortlist แล้วถามเลือกด้วย**ปุ่มกด** — หน้าแต่ละหน้าปุ่มสินค้า 3 อัน + ปุ่ม `[ ดูอันดับถัดไป ]` เลื่อนดูได้จนครบ (ปุ่ม "✏️ Other" พิมพ์หมายเลข/ชื่อได้ตลอด) แล้วแปะรูปสินค้า + ถามยืนยันอีกครั้ง `[ ยืนยัน ] [ เลือกใหม่ ] [ ค้นใหม่ ]` ก่อนสร้าง Product จริง (ค้นใหม่ = โชว์ keyword ล่าสุด 3 อันเป็นปุ่ม หรือใช้ "✏️ Other" พิมพ์ keyword ใหม่)
4. สั่ง `gen draft หูฟังบลูทูธ` → bot จะถามรีวิวด้วย**ปุ่มกด**:
   ```
   ❓ รีวิว draft ของ 'หูฟังบลูทูธ' — อนุมัติให้โพสต์ได้เลยไหม?
   [ อนุมัติ (approve) ]  [ ส่งกลับแก้ไข (reject) ]
   ```
5. กด **อนุมัติ** → bot ถามยืนยันโพสต์ด้วยปุ่ม `[ ยืนยันโพสต์ ] [ ไม่เอา ]` ทีละแพลตฟอร์ม (YouTube ก่อน แล้ว TikTok/Facebook)
6. (ห้ามปิดหน้าต่าง Gateway ขณะใช้งาน / รีสตาร์ท Hermes หลังแก้ skill)

---

## 📋 สรุปคำสั่งที่ต้องใช้บ่อย

| คำสั่ง | ใช้ทำอะไร |
|---|---|
| `& $hermes` | เริ่มคุยกับ Hermes ใน Terminal (ออกด้วย `/exit`) |
| `& $hermes gateway` | เปิด Telegram Gateway (ต้องเปิดค้างไว้) |
| `... factory_manager.py list` | ดูโรงงานที่มี (stages/phases/platforms) |
| `... create --factory <id> --name "<ชื่อ>"` | สร้าง Product |
| `... test --factory <id> --product "<slug>"` | รัน workflow ทดสอบพื้นฐาน |
| `... build --factory <id> --product "<slug>"` | สร้าง draft (เฟส 1) |
| `... review --product "<slug>" --status approve\|reject [--notes "..."]` | รีวิว (approve/reject) |
| `... publish --factory <id> --product "<slug>" [--platform youtube\|tiktok\|facebook]` | โพสต์ (เฟส 2) |
| `... status --product "<slug>"` | ดูสถานะ + published[] |
| `... artifacts --product "<slug>"` | ดูรายการไฟล์ที่ gen แล้ว |

> หมายเหตุ: `...` = `python C:\AI_FACTORY\shared\tools\`

---

## ⚠️ ข้อควรจำ

- เปิด PowerShell ใหม่ทุกครั้ง → **ต้องตั้งค่าขั้นตอนที่ 2 ใหม่**
- แก้ skill/config แล้ว → **รีสตาร์ท Hermes**
- (ทางเลือก) ใช้ Gemini เป็น model หลัก: ใส่ `GEMINI_API_KEY` ใน `shared\hermes_home\.env` แล้วรีสตาร์ท — **ยังไม่ใส่ก็ได้** ระบบจะใช้ fallback ฟรี (Nous Portal → OpenRouter) อัตโนมัติ (วิธีเช็คว่าใช้ตัวไหนจริง: Workthrough 5.3 / 10.4)
- ห้ามใส่ key ในโฟลเดอร์ product, log, หรือแชท — อยู่ใน `.env` เท่านั้น
- `publish` ต้องผ่านรีวิว (APPROVED) ก่อนเสมอ — `--force` ใช้เฉพาะเมื่อจำเป็นจริงๆ
- **วิดีโอฟรี 100%:** ใช้ ffmpeg ที่เครื่อง (`VIDEO_PROVIDER=ffmpeg`) ไม่ต้องใช้ API key ใดๆ — ใส่ภาพสินค้าที่ `images/` แล้ว `build` จะได้ `videos/promo.mp4` พร้อมเสียงพากย์จากสคริปต์โปรโมต (edge-tts, ไทย/อังกฤษอัตโนมัติ); **ถ้า export จาก research ภาพสินค้าจะถูกดาวน์โหลดลง `images/` อัตโนมัติ**
- วิดีโอ/สคริปต์/เสียงพากย์ทำจริงแล้วแบบฟรี; ยังเป็น placeholder เฉพาะ: โพสต์แพลตฟอร์มจริง, ค้นสินค้า Shopee API (รอ keys), EPUB/PDF

---

*รายละเอียดเชิงลึก สถาปัตยกรรม การแก้ปัญหา และแผนพัฒนา: ดู [Workthrough.md](Workthrough.md)*
