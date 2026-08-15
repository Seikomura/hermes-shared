#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
model-health-check.py — ตรวจโมเดล orchestration (OpenRouter) ทั้งหมดใน fallback chain

- อ่านรายชื่อโมเดลจาก `shared/hermes_home/config.yaml` อัตโนมัติ
  (primary + ทุก fallback ที่ provider == openrouter — ถ้า chain เปลี่ยนไม่ต้องแก้สคริปต์)
- ทดสอบพร้อมกัน (parallel): availability (HTTP 200?) + latency (วินาที)
- ใช้ key จาก `shared/hermes_home/.env` (OPENROUTER_API_KEY)

วิธีใช้:
  python model-health-check.py                 # ตรวจทั้งหมด (parallel 4)
  python model-health-check.py --parallel 8    # เพิ่ม concurrency
  python model-health-check.py --serial        # ทีละตัว (กัน rate-limit)
  python model-health-check.py --model <id>    # เฉพาะตัวเดียว
  python model-health-check.py --json          # output แบบ JSON (ใช้กับสคริปต์อื่น)
  python model-health-check.py --timeout 90    # ตั้ง timeout ต่อโมเดล (วิ)

exit code: 0 = ผ่านหมด, 1 = มีตัวที่ล้ม (ใช้กับ task scheduler / CI ได้)
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor

# บังคับ output เป็น UTF-8 (console Windows ใช้ cp1252 ฟ้องกับภาษาไทย)
if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if sys.stderr and hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# ---------------------------------------------------------------------------
# Paths — ใช้ HERMES_HOME env ถ้ามี ไม่งั้นค่า default
# ---------------------------------------------------------------------------
DEFAULT_HERMES_HOME = r"C:\AI_FACTORY\shared\hermes_home"
HERMES_HOME = os.environ.get("HERMES_HOME", DEFAULT_HERMES_HOME)
ENV_FILE = os.path.join(HERMES_HOME, ".env")
CONFIG_FILE = os.path.join(HERMES_HOME, "config.yaml")

API_URL = "https://openrouter.ai/api/v1/chat/completions"

# Fallback ถ้าอ่าน config ไม่ได้ — รายชื่อโมเดล orchestration (ตรงกับ config.yaml ณ 15 ส.ค. 2026)
FALLBACK_MODELS = [
    "nvidia/nemotron-3-ultra-550b-a55b:free",          # primary — agent orchestration
    "nvidia/nemotron-3.5-lightning:free",
    "poolside/laguna-s-2.1:free",
    "nvidia/nemotron-3-super-120b-a12b:free",
    "cohere/north-mini-code:free",
    "openai/gpt-oss-20b:free",
    "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
    "google/gemma-4-26b-a4b-it:free",
]

TEST_PROMPT = "Reply with OK only"
MAX_TOKENS = 100  # เผื่อ reasoning model (cohere/nano/gpt-oss ใช้ token ใน reasoning ก่อน)


def read_env_key(key_name):
    """อ่านค่า key จาก .env (รูปแบบ KEY=VALUE หนึ่งบรรทัดต่อตัว)"""
    try:
        with open(ENV_FILE, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if line.startswith(key_name + "="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    return None


def load_models_from_config():
    """แยก (provider, model) จาก config.yaml — คืนเฉพาะ openrouter (primary + fallback)"""
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8", errors="ignore") as f:
            text = f.read()
    except OSError:
        return None

    models = []
    # primary (model.default)
    m = re.search(r"^model:\s*$.*?^  default:\s*(\S+)", text, re.M | re.S)
    if m:
        models.append(m.group(1))

    # fallback_providers ที่ provider == openrouter (เรียงตาม config)
    section = re.search(r"^fallback_providers:\s*(.*?)(?=^auxiliary:|\Z)", text, re.M | re.S)
    if section:
        for block in re.finditer(r"^\s*-\s*provider:\s*(\S+)\s*\n\s*model:\s*(\S+)", section.group(1), re.M):
            prov, mod = block.group(1), block.group(2)
            if prov == "openrouter":
                models.append(mod)

    if not models:
        return None
    # คงลำดับ + ไม่ซ้ำ
    seen = set()
    return [x for x in models if not (x in seen or seen.add(x))]


def check_model(api_key, model, timeout):
    """ทดสอบ 1 โมเดล — คืน dict {model, ok, latency, status, note}"""
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": TEST_PROMPT}],
        "max_tokens": MAX_TOKENS,
    }).encode("utf-8")
    req = urllib.request.Request(
        API_URL, data=body, method="POST",
        headers={
            "Authorization": "Bearer " + api_key,
            "Content-Type": "application/json",
        },
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            latency = time.time() - t0
            raw = resp.read().decode("utf-8", "ignore")
            data = json.loads(raw)
        choice = (data.get("choices") or [{}])[0]
        finish = choice.get("finish_reason")
        provider = data.get("provider", "")
        content = (choice.get("message") or {}).get("content")
        note = f"route={provider}"
        if content is None:
            note += ", content=null (reasoning ยังไม่จบใน max_tokens?)"
        elif finish:
            note += f", finish={finish}"
        return {"model": model, "ok": True, "latency": round(latency, 1), "status": resp.status, "note": note}
    except urllib.error.HTTPError as e:
        latency = time.time() - t0
        note = ""
        try:
            err = json.loads(e.read().decode("utf-8", "ignore"))
            note = (err.get("error") or {}).get("message", "")[:110]
        except Exception:
            pass
        return {"model": model, "ok": False, "latency": round(latency, 1), "status": e.code, "note": note}
    except Exception as e:
        latency = time.time() - t0
        return {"model": model, "ok": False, "latency": round(latency, 1), "status": 0, "note": str(e)[:110]}


def main():
    ap = argparse.ArgumentParser(description="ตรวจโมเดล orchestration (OpenRouter) ใน fallback chain")
    ap.add_argument("--parallel", type=int, default=4, help="จำนวนโมเดลที่ทดสอบพร้อมกัน (default 4)")
    ap.add_argument("--serial", action="store_true", help="ทดสอบทีละตัว (parallel=1)")
    ap.add_argument("--model", help="ทดสอบเฉพาะโมเดลเดียว (id เต็ม เช่น nvidia/nemotron-3-ultra-550b-a55b:free)")
    ap.add_argument("--timeout", type=int, default=60, help="timeout ต่อโมเดล (วิ, default 60)")
    ap.add_argument("--json", action="store_true", help="แสดงผลเป็น JSON")
    args = ap.parse_args()

    workers = 1 if args.serial else max(1, args.parallel)

    api_key = read_env_key("OPENROUTER_API_KEY")
    if not api_key:
        print(f"[ERROR] ไม่พบ OPENROUTER_API_KEY ใน {ENV_FILE}", file=sys.stderr)
        sys.exit(2)

    if args.model:
        models = [args.model]
    else:
        models = load_models_from_config()
        if models is None:
            print(f"[WARN] อ่าน config.yaml ไม่ได้ ({CONFIG_FILE}) — ใช้รายชื่อ fallback", file=sys.stderr)
            models = FALLBACK_MODELS

    results = []
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = [ex.submit(check_model, api_key, m, args.timeout) for m in models]
        for f in futs:
            results.append(f.result())

    ok = [r for r in results if r["ok"]]
    failed = [r for r in results if not r["ok"]]

    if args.json:
        print(json.dumps({
            "checked": len(results), "ok": len(ok), "failed": len(failed),
            "models": results,
        }, ensure_ascii=False, indent=2))
    else:
        print(f"\n=== Model Health Check (OpenRouter orchestration) — {len(results)} โมเดล ===")
        print(f"key: {ENV_FILE}  |  concurrency: {workers}  |  timeout: {args.timeout}s\n")
        print(f"{'#':<3}{'สถานะ':<8}{'เวลา(วิ)':<9}{'HTTP':<6}โมเดล")
        print("-" * 90)
        for i, r in enumerate(results, 1):
            status = "OK " if r["ok"] else "FAIL"
            http = str(r["status"]) if r["status"] else "-"
            print(f"{i:<3}{status:<8}{r['latency']:<9}{http:<6}{r['model']}")
            if r["note"]:
                print(f"     └─ {r['note']}")
        print("-" * 90)
        print(f"ผลรวม: {len(ok)}/{len(results)} ผ่าน" + (" — ✅ ทั้งหมด OK" if not failed else f" — ❌ ล้ม {len(failed)} ตัว (ดูข้างบน)"))
        print("หมายเหตุ: ถ้าตัวใด 429 = rate-limit ชั่วคราว (รอสักครู่แล้วรันใหม่); 402 = ต้องเติมเครดิต\n")

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
