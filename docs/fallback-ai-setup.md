# Fallback AI Setup — สรุป config + คำสั่งเช็คสถานะ

> เอกสารย่อของระบบ AI แบบหลายชั้น: **Gemini (หลัก) → Nous ฟรี ×3 → OpenRouter ฟรี ×2 → LM Studio เครื่องทำงาน (Tailscale) → LM Studio เครื่องนี้ (สุดท้าย)**
> Config หลัก: `shared/hermes_home/config.yaml` (วันที่อัปเดตล่าสุด 14 ส.ค. 2026)
> 📎 เอกสารเต็ม: [Workthrough.md](Workthrough.md) (§4 สิ่งที่ต้องเตรียม · **§10.5 วิธีเช็คว่า bot ตอบผ่านชั้นไหน** · §14 Changelog) · [README.md](README.md) · [Quick-Start.md](Quick-Start.md)

---

## 🏗️ สถาปัตยกรรม

| เครื่อง | บทบาท |
|---|---|
| **เครื่องบ้าน** (เครื่องนี้, `C:\AI_FACTORY`) | รัน Hermes gateway + bot Telegram (`@Yo_Factory_bot`) — ใช้ cloud เป็นหลัก, local เป็นสำรอง |
| **เครื่องทำงาน** (`100.77.88.33` ผ่าน Tailscale) | LM Studio + `qwen/qwen3.5-9b` (port 1234) — ชั้น local fallback |
| **Nous Portal** | subscription (OAuth) — ตอนนี้ใช้ได้เฉพาะโมเดล **`:free`** (ยังไม่มีเครดิต) |

---

## 📋 Fallback chain ไฟนอล (7 ชั้น)

| ลำดับ | provider | model | หมายเหตุ |
|---|---|---|---|
| Primary | gemini | `gemini-3.6-flash` | หลัก — ทุก turn เริ่มที่ตัวนี้ |
| 1 | nous | `upstage/solar-pro4:free` | context 524K เหมาะงานยาว |
| 2 | nous | `tencent/hy3:free` | 295B reasoning + agentic |
| 3 | nous | `stepfun/step-3.7-flash:free` | multimodal + reasoning |
| 4 | openrouter | `nvidia/nemotron-3-ultra-550b-a55b:free` | 550B ฟรี |
| 5 | openrouter | `nvidia/nemotron-3-super-120b-a12b:free` | 120B ฟรี |
| 6 | custom | `qwen/qwen3.5-9b` @ `100.77.88.33:1234` | LM Studio เครื่องทำงาน (Tailscale) |
| 7 | lmstudio | `qwen/qwen3-1.7b` @ `127.0.0.1:1234` | **เครื่องนี้ — อันดับสุดท้าย** |

- `auxiliary.compression` ใช้ OpenRouter ฟรี (context 1M) — ไม่แตะ
- `custom_providers`: `lmstudio-work` (งาน, 64K) + `lmstudio-local` (เครื่องนี้, 32K)
- fallback เป็นแบบ **per-turn** — ทุกข้อความใหม่เริ่มที่ gemini ก่อนเสมอ

---

## 🔍 คำสั่งเช็คสถานะ

| ตรวจอะไร | คำสั่ง (PowerShell/CMD) |
|---|---|
| Chain fallback ปัจจุบัน | `hermes fallback list` |
| Credentials (gemini/openrouter/nous) | `hermes auth list` |
| สถานะ Nous Portal (login/subscription) | `hermes portal info` |
| เครื่องทำงาน LM Studio พร้อมไหม | `curl http://100.77.88.33:1234/v1/models` (ควรเห็น `qwen/qwen3.5-9b`) |
| LM Studio เครื่องนี้ | `curl http://127.0.0.1:1234/v1/models` |
| Tailscale เชื่อมต่อไหม | `tailscale status` |
| Gateway ทำงาน/เชื่อม Telegram หรือยัง | `Get-Content "C:\AI_FACTORY\shared\hermes_home\state\gateway.lifecycle.json"` |
| Bot ตอบผ่านชั้นไหนล่าสุด | `Get-Content "C:\AI_FACTORY\shared\hermes_home\logs\agent.log" -Tail 50 \| Select-String "turn:\|API call #1:\|Fallback activated\|100.77.88.33:1234"` — อธิบายแต่ละบรรทัด: **Workthrough §10.5** |
| ทดสอบคุยตรงผ่าน Nous ฟรี | `hermes chat -q "ตอบว่า OK" -Q --provider nous -m upstage/solar-pro4:free --max-turns 2` |
| ทดสอบคุยตรงผ่านเครื่องทำงาน | `hermes chat -q "ตอบว่า OK" -Q --provider lmstudio-work -m qwen/qwen3.5-9b --max-turns 2` |
| โมเดลฟรีทั้งหมดของ Nous | `curl -s https://inference-api.nousresearch.com/v1/models` (ดูตัวที่ pricing = 0) |

> 💡 คำสั่ง `hermes ...` ต้องตั้งค่า `$hermes` ก่อน (ดู Workthrough §5.2):
> ```powershell
> $env:HERMES_HOME='C:\AI_FACTORY\shared\hermes_home'
> $hermes='C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe'
> ```
> แล้วใช้ `& $hermes fallback list` / `& $hermes chat ...` แทนคำว่า `hermes` ในตาราง

---

## 📜 สคริปต์ที่เกี่ยวข้อง

| ไฟล์ | สำหรับ | ใช้ที่ไหน |
|---|---|---|
| `shared/tools/work-lmstudio-autostart.ps1` | เปิด LM Studio + โหลด qwen3.5-9b + server (bind 0.0.0.0) อัตโนมัติตอน login | **เครื่องทำงาน** (คัดลอกไป) |
| `Downloads/home-use-work-local.ps1` | เปลี่ยน config เครื่องบ้านให้ชี้ LM Studio เครื่องทำงาน + restart | **เครื่องบ้าน** |

---

## ⚠️ ข้อควรจำ

1. **เครื่องทำงานต้องเปิดค้างไว้ + LM Studio รันตลอด** — ไม่งั้นชั้น 6 ใช้ไม่ได้ (ชั้น cloud ยังทำงาน)
2. **Nous ยังไม่มีเครดิต** — ใช้ได้เฉพาะตัว `:free` (solar-pro4 / hy3 / stepfun); ตัวเสียเงิน (เช่น claude-sonnet-4.6) จะ error 404 `requires credits` — เติมเครดิตที่ portal.nousresearch.com ถ้าอยากใช้
3. **อย่าใช้ `--provider custom` ในการทดสอบ** — มัน resolve ไป OpenRouter; ใช้ `--provider lmstudio-work` ถึงจะไปเครื่องทำงานจริง
4. ตรวจว่า bot ตอบผ่านเครื่องทำงานจริง: grep `100.77.88.33:1234` ใน `logs\agent.log` (วิธีละเอียด + ตัวอย่างบรรทัด log: **Workthrough §10.5**)
