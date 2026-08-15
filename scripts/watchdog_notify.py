#!/usr/bin/env python3
"""
AI FACTORY - Gateway restart Telegram notifier (stdlib only, no packages).

Watches logs/watchdog.log (written by start_gateway.bat on every gateway
restart) and sends each NEW line to the allowed Telegram users via the
Telegram Bot API. Called by start_gateway.bat right after it logs a restart;
can also be run manually.

Usage:
  python watchdog_notify.py             # send un-notified new lines (default)
  python watchdog_notify.py --dry-run   # print what would be sent, send nothing
  python watchdog_notify.py --force     # ignore state: send every line in the log
  python watchdog_notify.py --log <path> --state <path>   # override (tests)

Behavior:
  - First run with no state file: records the current line count WITHOUT
    sending (past restarts are not reported retroactively).
  - State advances only after a successful send, so a failed send is retried
    on the next run (delayed delivery).
  - If the log is truncated/rotated, the baseline resets without sending.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERMES_HOME = Path(os.environ.get("HERMES_HOME", r"C:\AI_FACTORY\shared\hermes_home"))
DEFAULT_ENV = HERMES_HOME / ".env"
DEFAULT_LOG = HERMES_HOME / "logs" / "watchdog.log"
DEFAULT_STATE = HERMES_HOME / "logs" / ".watchdog_notify_state.json"
MAX_LINES_PER_MESSAGE = 10


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


def build_message(lines: list) -> str:
    gave_up = any("giving up" in ln.lower() for ln in lines)
    if gave_up:
        header = "⛔ AI FACTORY - Gateway restart ล้มเหลวซ้ำ (watchdog ยอมแพ้)\nตรวจ config หรือ logs\\gateway.log"
    else:
        header = "⚠️ AI FACTORY - Gateway ถูก restart อัตโนมัติ"
    shown = lines[:MAX_LINES_PER_MESSAGE]
    body = "\n".join(f"\u2022 {ln}" for ln in shown)
    if len(lines) > MAX_LINES_PER_MESSAGE:
        body += f"\n\u2026 และอีก {len(lines) - MAX_LINES_PER_MESSAGE} เหตุการณ์"
    return f"{header}\n{body}"


def main() -> int:
    # Windows console/log files may default to cp1252 (Thai system) and crash on
    # Thai/emoji output - force UTF-8 with lossless fallback for all prints.
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    ap = argparse.ArgumentParser(description="AI FACTORY gateway-restart Telegram notifier")
    ap.add_argument("--dry-run", action="store_true", help="print what would be sent, send nothing")
    ap.add_argument("--force", action="store_true", help="ignore state: send every line in the log")
    ap.add_argument("--log", default=str(DEFAULT_LOG), help="watchdog.log path")
    ap.add_argument("--state", default=str(DEFAULT_STATE), help="state file path")
    args = ap.parse_args()

    log_path = Path(args.log)
    state_path = Path(args.state)
    if not log_path.exists():
        print(f"[notify] no log at {log_path} - nothing to do")
        return 0

    # Only restart/give-up events are notified; the watchdog's own
    # "stop requested" audit line is skipped.
    lines = [
        ln.rstrip("\r\n")
        for ln in log_path.read_text(encoding="utf-8", errors="ignore").splitlines()
        if ln.strip() and "stop requested" not in ln
    ]
    total = len(lines)
    prev = read_state(state_path)

    if args.force:
        start = 0
    elif prev < 0:
        # First ever run: baseline without sending (past restarts not reported).
        start = total
        print(f"[notify] first run - baseline at {total} lines (no send)")
        write_state(state_path, total)
        return 0
    elif prev > total:
        # Log truncated/rotated: reset baseline, do not spam old lines.
        start = total
        print(f"[notify] log truncated ({prev} -> {total}) - re-baselined (no send)")
        write_state(state_path, total)
        return 0
    else:
        start = prev

    new_lines = lines[start:]
    if not new_lines:
        print("[notify] no new lines")
        return 0

    env = load_env(DEFAULT_ENV)
    token = env.get("TELEGRAM_BOT_TOKEN", "")
    users = allowed_users(env, HERMES_HOME / "channel_directory.json")
    if not token or not users:
        print(
            f"[notify] WARN: missing TELEGRAM_BOT_TOKEN or allowed users - "
            f"{len(new_lines)} line(s) pending (state not advanced)"
        )
        return 2

    text = build_message(new_lines)
    if args.dry_run:
        print(f"[notify] DRY-RUN would send to {users}:\n{text}")
        return 0

    sent_ok = True
    for chat_id in users:
        try:
            result = send_telegram(token, chat_id, text)
            ok = bool(result.get("ok"))
            print(f"[notify] sent to {chat_id}: ok={ok}")
            sent_ok = sent_ok and ok
        except Exception as exc:
            print(f"[notify] FAILED to {chat_id}: {exc}")
            sent_ok = False

    if sent_ok:
        write_state(state_path, total)
        print(f"[notify] state advanced to {total}")
    else:
        print("[notify] send failed - state NOT advanced (will retry on next run)")
    return 0 if sent_ok else 1


if __name__ == "__main__":
    sys.exit(main())
