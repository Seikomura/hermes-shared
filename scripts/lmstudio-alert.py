#!/usr/bin/env python3
"""
AI FACTORY - LM Studio fallback alert (stdlib only, no packages).

Watches logs/agent.log for conversation turns that fell through the ENTIRE
fallback chain down to the last layer (provider=lmstudio = qwen3-1.7b on THIS
machine — CPU-only, ~1 min/round at large contexts, can exceed Hermes' 900s
stream timeout). Sends ONE Telegram message per such turn so you know a reply
may take minutes or never arrive.

Called by gateway-watch.ps1 (runs every 2 min via HermesGatewayWatch task).
State file prevents re-sending the same turn.

Usage:
  python lmstudio-alert.py             # send alerts for new lmstudio turns
  python lmstudio-alert.py --dry-run   # print what would be sent, send nothing
  python lmstudio-alert.py --force     # ignore state: alert every matching line
  python lmstudio-alert.py --log <path> --state <path>   # override (tests)

Behavior:
  - Only lines matching "conversation turn: ... provider=lmstudio" count as
    events (one alert per turn; client-init/API-call lines are ignored).
  - First run with no state file: records the current line count WITHOUT
    sending (past turns are not reported retroactively).
  - State advances only after a successful send, so a failed send is retried
    on the next run (delayed delivery).
  - If the log is truncated/rotated, the baseline resets without sending.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERMES_HOME = Path(os.environ.get("HERMES_HOME", r"C:\AI_FACTORY\shared\hermes_home"))
DEFAULT_ENV = HERMES_HOME / ".env"
DEFAULT_LOG = HERMES_HOME / "logs" / "agent.log"
DEFAULT_STATE = HERMES_HOME / "logs" / ".lmstudio_alert_state.json"
MAX_LINES_PER_MESSAGE = 8

# 1 บรรทัด = 1 turn ที่ตกถึง lmstudio (กัน alert ซ้ำจาก client created / API call lines)
TURN_PATTERN = re.compile(r"conversation turn: .*provider=lmstudio")


def load_env(path: Path) -> dict:
    vals: dict = {}
    if path.exists():
        for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            vals[key.strip()] = value.strip().strip('"').strip("'")
    return vals


def allowed_users(env: dict, channel_dir: Path) -> list:
    """Chat IDs from TELEGRAM_ALLOWED_USERS (comma/space/semicolon separated),
    falling back to channel_directory.json (platforms.telegram[].id)."""
    raw = env.get("TELEGRAM_ALLOWED_USERS", "")
    ids = [p for p in raw.replace(";", ",").replace(" ", ",").split(",") if p.strip()]
    if not ids and channel_dir.exists():
        try:
            data = json.loads(channel_dir.read_text(encoding="utf-8"))
            ids = [u["id"] for u in data.get("platforms", {}).get("telegram", []) if u.get("id")]
        except Exception:
            ids = []
    return ids


def send_telegram(token: str, chat_id: str, text: str) -> dict:
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    body = urllib.parse.urlencode(
        {"chat_id": chat_id, "text": text, "disable_web_page_preview": "true"}
    ).encode("utf-8")
    req = urllib.request.Request(url, data=body)
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


def read_state(path: Path) -> int:
    if not path.exists():
        return -1  # no state yet -> first run baseline
    try:
        return int(json.loads(path.read_text(encoding="utf-8")).get("lines_read", 0))
    except Exception:
        return -1


def write_state(path: Path, lines_read: int) -> None:
    data = {
        "lines_read": lines_read,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def extract_msg(line: str) -> str:
    m = re.search(r"msg='(.*?)'$", line)
    if m:
        return m.group(1)[:120]
    m2 = re.search(r"history=\d+ (.*)$", line)
    return (m2.group(1)[:120] if m2 else "")


def build_message(lines: list) -> str:
    header = (
        "🐌 Bot ตกถึงชั้นสุดท้าย (LM Studio ⑭ — qwen3-1.7b, CPU-only)!\n"
        "ตอบอาจช้าเป็นนาที หรือเกิน 15 นาทีจนถูกตัด — ถ้าไม่เร่งด่วน รอ/ส่งใหม่ก็ได้"
    )
    shown = lines[:MAX_LINES_PER_MESSAGE]
    parts = []
    for ln in shown:
        ts = ln[:19]
        msg = extract_msg(ln)
        parts.append(f"• {ts} msg='{msg}'" if msg else f"• {ts}")
    body = "\n".join(parts)
    if len(lines) > MAX_LINES_PER_MESSAGE:
        body += f"\n… และอีก {len(lines) - MAX_LINES_PER_MESSAGE} turn"
    return f"{header}\n{body}"


def main() -> int:
    # Windows console/log files may default to cp1252 (Thai system) and crash on
    # Thai/emoji output - force UTF-8 with lossless fallback for all prints.
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    ap = argparse.ArgumentParser(description="AI FACTORY LM Studio fallback alert")
    ap.add_argument("--dry-run", action="store_true", help="print what would be sent, send nothing")
    ap.add_argument("--force", action="store_true", help="ignore state: alert every matching line")
    ap.add_argument("--log", default=str(DEFAULT_LOG), help="agent.log path")
    ap.add_argument("--state", default=str(DEFAULT_STATE), help="state file path")
    args = ap.parse_args()

    log_path = Path(args.log)
    state_path = Path(args.state)
    if not log_path.exists():
        print(f"[lmstudio-alert] no log at {log_path} - nothing to do")
        return 0

    all_lines = log_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    total = len(all_lines)
    prev = read_state(state_path)

    if args.force:
        start = 0
    elif prev < 0:
        # First ever run: baseline without sending (past turns not reported).
        start = total
        print(f"[lmstudio-alert] first run - baseline at {total} lines (no send)")
        write_state(state_path, total)
        return 0
    elif prev > total:
        # Log truncated/rotated: reset baseline, do not spam old lines.
        start = total
        print(f"[lmstudio-alert] log truncated ({prev} -> {total}) - re-baselined (no send)")
        write_state(state_path, total)
        return 0
    else:
        start = prev

    new_events = [ln for ln in all_lines[start:] if TURN_PATTERN.search(ln)]
    if not new_events:
        print("[lmstudio-alert] no new lmstudio turns")
        return 0

    env = load_env(DEFAULT_ENV)
    token = env.get("TELEGRAM_BOT_TOKEN", "")
    users = allowed_users(env, HERMES_HOME / "channel_directory.json")
    if not token or not users:
        print(
            f"[lmstudio-alert] WARN: missing TELEGRAM_BOT_TOKEN or allowed users - "
            f"{len(new_events)} event(s) pending (state not advanced)"
        )
        return 2

    text = build_message(new_events)
    if args.dry_run:
        print(f"[lmstudio-alert] DRY-RUN would send to {users}:\n{text}")
        return 0

    sent_ok = True
    for chat_id in users:
        try:
            result = send_telegram(token, chat_id, text)
            ok = bool(result.get("ok"))
            print(f"[lmstudio-alert] sent to {chat_id}: ok={ok}")
            sent_ok = sent_ok and ok
        except Exception as exc:
            print(f"[lmstudio-alert] FAILED to {chat_id}: {exc}")
            sent_ok = False

    if sent_ok:
        write_state(state_path, total)
        print(f"[lmstudio-alert] state advanced to {total}")
    else:
        print("[lmstudio-alert] send failed - state NOT advanced (will retry on next run)")
    return 0 if sent_ok else 1


if __name__ == "__main__":
    sys.exit(main())
