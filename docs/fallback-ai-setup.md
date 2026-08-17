# Fallback AI Setup — สรุป config + คำสั่งเช็คสถานะ

> เอกสารย่อของระบบ AI แบบหลายชั้น: **OpenRouter (หลัก — orchestration 8 ตัว) → Nous ฟรี ×3 → Gemini**
> ⚠️ **17 ส.ค. 2026: ลบ LM Studio ออกหมดแล้ว (ทั้งเครื่องนี้ + เครื่องทำงานผ่าน Tailscale) — เหลือ API เท่านั้น** (ดู Workthrough §14 v12)
> Config หลัก: `shared/hermes_home/config.yaml` (อัปเดตล่าสุด 17 ส.ค. 2026)
> 📎 เอกสารเต็ม: [Workthrough.md](Workthrough.md) (§4 สิ่งที่ต้องเตรียม · **§10.5 วิธีเช็คว่า bot ตอบผ่านชั้นไหน** · §14 Changelog) · [README.md](README.md) · [Quick-Start.md](Quick-Start.md)

---

## 🏗️ สถาปัตยกรรม

| เครื่อง | บทบาท |
|---|---|
| **เครื่องบ้าน** (เครื่องนี้, `C:\AI_FACTORY`) | รัน Hermes gateway + bot Telegram (`@Yo_Factory_bot`) — ใช้ cloud API ทั้งหมด (OpenRouter + Nous + Gemini) |
| **Nous Portal** | subscription (OAuth) — ตอนนี้ใช้ได้เฉพาะโมเดล **`:free`** (ยังไม่มีเครดิต) |

> ระบบไม่พึ่งเครื่องอื่น/Local AI อีกแล้ว — ทำงานได้แม้เครื่องทำงานปิด

---

## 📋 Fallback chain ไฟนอล (primary + 11 ชั้น — orchestration-first, API เท่านั้น)

| ลำดับ | provider | model | หมายเหตุ |
|---|---|---|---|
| Primary | openrouter | `nvidia/nemotron-3-ultra-550b-a55b:free` | 🎯 หลัก — **agent orchestration** (550B, 1M ctx) |
| 1 | openrouter | `nvidia/nemotron-3.5-lightning:free` | 1M ctx, reasoning, รุ่นใหม่สุด |
| 2 | openrouter | `poolside/laguna-s-2.1:free` | agentic coding (Terminal-Bench 70.2%) |
| 3 | openrouter | `nvidia/nemotron-3-super-120b-a12b:free` | MTP, accuracy สูง (AIME/SWE-Bench) |
| 4 | openrouter | `cohere/north-mini-code:free` | JSON schema tool use |
| 5 | openrouter | `openai/gpt-oss-20b:free` | function calling, structured outputs |
| 6 | openrouter | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free` | multimodal (ภาพ/วิดีโอ/เสียง) |
| 7 | openrouter | `google/gemma-4-26b-a4b-it:free` | native function calling (บางช่วง 429 จาก Google) |
| 8 | nous | `upstage/solar-pro4:free` | context 524K เหมาะงานยาว |
| 9 | nous | `tencent/hy3:free` | 295B reasoning + agentic |
| 10 | nous | `stepfun/step-3.7-flash:free` | multimodal + reasoning |
| 11 | gemini | `gemini-3.6-flash` | AI Studio — ใช้ `GEMINI_API_KEY` |

- `auxiliary.compression` ใช้ OpenRouter ฟรี (context 1M) — ไม่แตะ
- **ไม่มี `custom_providers` อีกแล้ว** (ถอดออกพร้อม LM Studio)
- fallback เป็นแบบ **per-turn** — ทุกข้อความใหม่เริ่มที่ Nemotron 3 Ultra (OpenRouter) ก่อนเสมอ

---

## 🔍 คำสั่งเช็คสถานะ

| ตรวจอะไร | คำสั่ง (PowerShell/CMD) |
|---|---|
| Chain fallback ปัจจุบัน (12 ชั้น) | `hermes fallback list` |
| โมเดล orchestration ทั้ง 8 ตัว พร้อมไหม (availability + latency) | `python C:\AI_FACTORY\shared\tools\model-health-check.py` — ผ่านหมด = exit 0; 429 = rate-limit ชั่วคราว; เพิ่ม `--json` สำหรับ automation |
| Credentials (gemini/openrouter/nous) | `hermes auth list` |
| สถานะ Nous Portal (login/subscription) | `hermes portal info` |
| Gateway ทำงาน/เชื่อม Telegram หรือยัง | `Get-Content "C:\AI_FACTORY\shared\hermes_home\state\gateway.lifecycle.json"` |
| Bot ตอบผ่านชั้นไหนล่าสุด | `Get-Content "C:\AI_FACTORY\shared\hermes_home\logs\agent.log" -Tail 50 \| Select-String "turn:\|API call #1:\|Fallback activated"` — อธิบายแต่ละบรรทัด: **Workthrough §10.5** |
| ทดสอบคุยตรงผ่าน Nous ฟรี | `hermes chat -q "ตอบว่า OK" -Q --provider nous -m upstage/solar-pro4:free --max-turns 2` |
| ทดสอบคุยตรงผ่าน Gemini | `hermes chat -q "ตอบว่า OK" -Q --provider gemini -m gemini-3.6-flash --max-turns 2` |
| โมเดลฟรีทั้งหมดของ Nous | `curl -s https://inference-api.nousresearch.com/v1/models` (ดูตัวที่ pricing = 0) |

> 💡 คำสั่ง `hermes ...` ต้องตั้งค่า `$hermes` ก่อน (ดู Workthrough §5.2):
> ```powershell
> $env:HERMES_HOME='C:\AI_FACTORY\shared\hermes_home'
> $hermes='C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe'
> ```
> แล้วใช้ `& $hermes fallback list` / `& $hermes chat ...` แทนคำว่า `hermes` ในตาราง

---

## ⚠️ ข้อควรจำ

1. **ระบบเป็น API 100% (v12)** — ไม่ต้องเปิด LM Studio / เครื่องทำงาน / Tailscale อีกแล้ว; ทำงานได้ทุกที่ที่มีอินเทอร์เน็ต
2. **Nous ยังไม่มีเครดิต** — ใช้ได้เฉพาะตัว `:free` (solar-pro4 / hy3 / stepfun); ตัวเสียเงิน (เช่น claude-sonnet-4.6) จะ error 404 `requires credits` — เติมเครดิตที่ portal.nousresearch.com ถ้าอยากใช้
3. **Gemini ต้องมี `GEMINI_API_KEY`** ใน `shared\hermes_home\.env` ถึงจะใช้ชั้น ⑫ ได้ — ไม่มี key Hermes จะข้ามไป (แต่ถ้าเป็นชั้นสุดท้ายจะค้าง timeout)
4. ตรวจว่า bot ตอบผ่านชั้นไหน: grep `provider=` ใน `logs\agent.log` (วิธีละเอียด + ตัวอย่างบรรทัด log: **Workthrough §10.5**)

---

📚 **เอกสารที่เกี่ยวข้อง:** [SYSTEM-OVERVIEW.md](SYSTEM-OVERVIEW.md) (ภาพรวมระบบ 1 หน้า) · [Workthrough.md](Workthrough.md) (เชิงลึก/การแก้ปัญหา/Changelog) · [Quick-Start.md](Quick-Start.md) (เริ่มใช้ด่วน)
