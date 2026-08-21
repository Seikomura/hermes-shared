# กฎการทำงาน (Hermes Agent)

## 🔴 ห้ามแตะ venv ของ Hermes เอง
- **ห้าม** รัน `pip install` / `uv pip install` / `uv add` / `python -m pip` ลงใน venv ของ Hermes
  (โฟลเดอร์ `C:\Users\suras\AppData\Local\hermes\hermes-agent\venv`) เด็ดขาด
- ถ้าต้องการติดตั้ง package สำหรับโปรเจกต์ → **สร้าง venv แยกของโปรเจกต์เสมอ** เช่น:
  `python -m venv .venv` แล้วใช้ `.venv\Scripts\pip install ...`
- เหตุผล: เคยเกิดเหตุการณ์ pip install โดนตัดกลางคัน → pydantic ใน venv หาย → bot เงียบทั้งระบบ

## 🛠️ ถ้า venv พัง (pydantic/openai import ไม่ได้)
ซ่อมด้วย:
```
uv pip install --python "C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe" "pydantic==2.13.4"
```
แล้ว restart gateway (schtasks /run /tn HermesGateway)

## 🔴 ไม่มี Local AI (LM Studio / Ollama / Tailscale)
- **ห้าม** พิมพ์/สั่งติดตั้ง LM Studio, Ollama, หรือ Tailscale ลงเครื่องนี้
- **ห้าม** สร้าง `custom_providers` ใน config.yaml (ไม่มี server ให้เชื่อม)
- **ห้าม** เปิด port 1234/11434 หรือตั้งค่า network ไปยังเครื่องอื่น
- **ห้าม** รัน `pip install fastapi/uvicorn` ลง venv ของ Hermes (เคยทำให้ pydantic หาย — ดูข้อบน)
- ระบบเป็น **API ล้วน** (OpenRouter + Nous + Gemini) — ไม่ต้องพึ่งเครื่องอื่น
- ถ้า user ขอให้ตั้ง local AI → แจ้งว่า "ระบบปัจจุบันใช้ API ล้วน ไม่มี local AI"
