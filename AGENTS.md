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
