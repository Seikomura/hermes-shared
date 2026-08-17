# AI Factory

Hermes Agent runs natively on Windows as the Factory Manager. Its state lives in `C:\AI_FACTORY\shared\hermes_home`; all product assets live only in `C:\AI_FACTORY\products\<windows-safe-slug>`.

> 📚 เอกสารเต็ม (ไทย): [SYSTEM-OVERVIEW.md](SYSTEM-OVERVIEW.md) (ภาพรวมระบบ 1 หน้า — แชร์ทีม) · [Workthrough.md](Workthrough.md) (แก้ปัญหาครบ + Changelog) · เริ่มใช้ด่วน: [Quick-Start.md](Quick-Start.md) · fallback config: [FALLBACK-AI-SETUP.md](FALLBACK-AI-SETUP.md)

## What it does

A **two-phase production workflow** for content products, controlled from a terminal or the Telegram bot:

```
create → build (draft) → review (approve gate) → publish (per platform)
```

- **build** generates the draft. For Shopee this is research → selection → script → assets → video → captions. The `script` and `video` stages are **real and 100% free** (see "Free video & voiceover" below); the other stages write placeholders until real providers are enabled.
- **review** is a gate: `publish` refuses to run unless the draft was approved.
- **publish** posts per platform for Shopee (YouTube → TikTok → Facebook, one at a time) and tracks `published[]` so nothing is posted twice. E-books have a single publishing step.

## Architecture

`shared\tools\factory_manager.py` discovers factories from `factories\<factory-id>\config\factory.json`; it has no factory-specific `if/else` routing. Add future factories by adding their own config, workflow, prompts/scripts, README, and factory-local `.env`.

Current factories:

- `shopee_affiliate`: research → selection → script → assets → video → captions → social_posts → publishing (per-platform publish: youtube, tiktok, facebook).
- `ebook`: research → outline → chapter_writer → editor → fact_check → cover_images → epub → pdf → publishing.

Helper tools (all free, no API keys needed for the video pipeline):

| Tool | Purpose |
|---|---|
| `shared/tools/shopee_research.py` | Search Shopee affiliate products (extra commission + high sales), export the pick into a product, list recent search keywords. Requires Shopee Affiliate API keys (not configured yet). |
| `shared/tools/script_writer.py` | Writes a real promo script (`[voiceover]` + `[details]`) to `scripts/script.txt` from research/selection data. |
| `shared/tools/video_builder.py` | Assembles the promo video locally with ffmpeg + a free Edge TTS voiceover. |

## Key locations

- `C:\AI_FACTORY\shared\hermes_home\.env`: `GEMINI_API_KEY`, `OPENROUTER_API_KEY`, `TELEGRAM_BOT_TOKEN`, and `TELEGRAM_ALLOWED_USERS`.
- `C:\AI_FACTORY\factories\shopee_affiliate\.env`: Shopee affiliate, video/image provider, YouTube, TikTok, and Facebook credentials. `VIDEO_PROVIDER=ffmpeg` is the free default.
- `C:\AI_FACTORY\factories\ebook\.env`: E-book-specific credentials when needed.

All `.env` files are ignored by Git. Never put any key in product folders, logs, README files, or chat messages.

## Quick Start: every new PowerShell window

Run this before starting Hermes or its Telegram Gateway:

```powershell
$env:HERMES_HOME='C:\AI_FACTORY\shared\hermes_home'
$env:AI_FACTORY_ROOT='C:\AI_FACTORY'
$hermes='C:\Users\suras\AppData\Local\hermes\hermes-agent\venv\Scripts\hermes.exe'
```

`HERMES_HOME` tells Hermes where its configuration, keys, skills, and logs live. `AI_FACTORY_ROOT` identifies the factory workspace. Define `$hermes` again in every new PowerShell window.

## Free video & voiceover (no API keys)

`VIDEO_PROVIDER=ffmpeg` (the default) builds promo videos entirely on this machine:

- **Video:** `video_builder.py` turns product images from `products\<slug>\images\` into `videos/promo.mp4` (720p@30fps, Ken Burns effect, product name caption). With no images it renders a title card. Requires ffmpeg (free): `winget install Gyan.FFmpeg`.
- **Voiceover:** a free Microsoft Edge TTS voice (`edge-tts`, auto Thai/English) narrates the script's `[voiceover]` section; the video length adapts to the narration. Install (free): `pip install edge-tts`. If it's missing or offline, the video is built silently without audio.
- **Script:** `script_writer.py` builds a real promo script (features/price/promo) from `research/` + `source_data/`; exported Shopee data flows straight into it.
- Build never overwrites real data — placeholder stages only create files that are missing or still placeholders.

**Known lessons (2026-08-15, first real promo.mp4 via the bot):**

- **Always edit skills with a quoted `description`** in the YAML frontmatter. A `:` (colon+space) inside the description silently breaks the YAML parse → the skill is hidden from the system prompt (check `.skills_prompt_snapshot.json` for `"description": ""`).
- **After editing a skill:** restart the gateway (`schtasks /Run /TN "AI_Factory_Gateway"` after killing the old chain) **and** type `/new` in Telegram — an old session keeps its stored system prompt, so restart alone is not enough.
- **`edge-tts` fails intermittently** (`NoAudioReceived`, transient network to Microsoft). The video still builds silently; retry the build (e.g. `python shared\tools\video_builder.py --product "<slug>"`) and verify with `ffprobe -select_streams a` that the AAC audio stream is present.
- **Verified pipeline:** `create → build → script.txt → video_builder.py → videos/promo.mp4` (1280×720, h264+aac, Thai voiceover) — 100% free, no API keys.

## Commands

> `...` = `python C:\AI_FACTORY\shared\tools\factory_manager.py`

| Command | Purpose |
|---|---|
| `& $hermes` | Start an interactive Hermes session (exit with `/exit` or Ctrl+C). Restart after changing skills/config. |
| `& $hermes gateway` | Start the Telegram Gateway manually (keep this window open while using the bot). |
| `schtasks /Run /TN "AI_Factory_Gateway"` | Start the Gateway via Task Scheduler (registered: auto-starts at logon, hidden window, watchdog auto-restart ~30s + task restart backup). |
| `shared\tools\stop_gateway.bat` | Stop the Gateway watchdog cleanly (stays stopped; `schtasks /End` alone is not enough). |
| `... list` | List registered factories (stages, phases, publish platforms). |
| `... create --factory <id> --name "<name>"` | Create a Product workspace. |
| `... test --factory <id> --product "<slug>"` | Run the foundation test workflow (placeholders only). |
| `... build --factory <id> --product "<slug>"` | Build the draft (`DRAFT_READY`; resets review to pending). |
| `... review --product "<slug>" --status approve\|reject [--notes "..."]` | Review gate (approve only after a build). |
| `... publish --factory <id> --product "<slug>" [--platform youtube\|tiktok\|facebook]` | Publish (requires APPROVED; `--force` bypasses gates). |
| `... status --product "<slug>"` | Show status, phase, review, `published[]`. |
| `... artifacts --product "<slug>"` | List generated files. |
| `python C:\AI_FACTORY\shared\tools\model-health-check.py` | Check availability + latency of all 8 orchestration (OpenRouter) models in the fallback chain (reads model list from `config.yaml`; exit 0 = all OK, 1 = some failed, 2 = no key). Add `--json` for automation. |

### Shopee product research (before creating)

```powershell
python C:\AI_FACTORY\shared\tools\shopee_research.py search --query "<keyword>"        # ranked shortlist (commission>=15%, sales>=500, incl. AMS)
python C:\AI_FACTORY\shared\tools\shopee_research.py export --product "<slug>" --index <n>  # import pick: real data + auto-download product photo
python C:\AI_FACTORY\shared\tools\shopee_research.py recent --limit 3                  # last 3 search keywords (re-search buttons)
```

Requires an approved Shopee Affiliate account + whitelist access for the Affiliate Open API (fill `factories\shopee_affiliate\.env`). Without keys the tool reports the setup steps instead of inventing data.

## Use the Telegram bot

Once the Gateway reports it is connected, send the bot a private message (see Workthrough for the full button walkthrough):

```text
/ai-factory หาสินค้า Shopee คอมมิชชันดี ขายดี หน่อย
/ai-factory สร้าง Product Shopee ชื่อ หูฟังบลูทูธ
```

The `ai-factory` skill (v1.14.0) creates real Products through the Factory Manager rather than returning a text listing. Confirmations render as **tappable inline buttons** via the `clarify` tool:

- **Pick a product** from the research shortlist: item buttons `[ #1 … ] [ #2 … ] [ #3 … ]` + a `[ ดูอันดับถัดไป ]` page button (the clarify cap is 4 choices), plus `✏️ Other` to type.
- **Confirm before creating**: product photo + `[ ยืนยัน ] [ เลือกใหม่ ] [ ค้นใหม่ ]` (ค้นใหม่ offers the last 3 keywords as buttons).
- **Review**: `[ อนุมัติ (approve) ] [ ส่งกลับแก้ไข (reject) ]` after build.
- **Publish**: `[ ยืนยันโพสต์ ] [ ไม่เอา ]` before every platform.

The same commands work for E-books by naming an E-book.

## Gateway auto-start at logon (Task Scheduler)

A scheduled task **`AI_Factory_Gateway`** is registered so the Telegram Gateway starts automatically every time you log into Windows — no need to keep a terminal window open:

- Hidden window via `wscript.exe` → `shared\tools\start_gateway_hidden.vbs` → `shared\tools\start_gateway.bat` (sets `HERMES_HOME`/`AI_FACTORY_ROOT` + runs `hermes gateway`, with a PID guard against double-starting).
- **Auto-restart (2 layers):** ① a **watchdog loop inside the .bat** (primary) relaunches the Gateway ~10s after it dies — tested: killed the Gateway and it was `connected` again in ~30s. It logs every restart to `logs\watchdog.log` and stops after 6 consecutive fast fails (died within 60s of start — crash-loop guard for broken configs). ② Task Scheduler "restart on failure" (3×, 1 min apart) is the backup for when the watchdog itself is killed. ⚠️ Task Scheduler restart-on-failure does **not** fire for manually started runs (`schtasks /Run`) — only for trigger-started (logon) runs — so the watchdog is what guarantees recovery.
- **Telegram alert on restart:** every `watchdog.log` entry is pushed to the allowed Telegram users by `shared\tools\watchdog_notify.py` (state in `logs\.watchdog_notify_state.json`, send log in `logs\notify.log`; only new lines, "stop requested" lines skipped). Tested: killed the Gateway → alert received.
- **Stop cleanly:** `shared\tools\stop_gateway.bat` — `schtasks /End` alone is NOT enough (the watchdog survives and relaunches); the stop script writes a stop marker + kills the processes so it stays stopped.
- Re-register anytime: `powershell -ExecutionPolicy Bypass -File C:\AI_FACTORY\shared\tools\register_gateway_task.ps1`; delete with `schtasks /Delete /TN "AI_Factory_Gateway" /F`.
- Run it on demand: `schtasks /Run /TN "AI_Factory_Gateway"`. Check it is alive via `shared\hermes_home\state\gateway.lifecycle.json` (`phase: running`) or `gateway_state.json` (`telegram.state: connected`).

## Watch the Gateway log

```powershell
Get-Content C:\AI_FACTORY\shared\hermes_home\logs\gateway.log -Wait
```

Streams Gateway events live. Use it first when the bot does not connect or reply. Do not share log excerpts that contain private account links or credentials.

## Current provider configuration

Models are configured as an **OpenRouter primary + 11-tier fallback chain — API only** (orchestration-first, LM Studio/Tailscale removed on 17 Aug 2026 — see Workthrough v12) in `shared\hermes_home\config.yaml`:

1. **OpenRouter** (primary, free): `nvidia/nemotron-3-ultra-550b-a55b:free` — 550B (55B active), 1M context, built for **agent orchestration** / coding / deep research.
2. **OpenRouter free**: `nvidia/nemotron-3.5-lightning:free` — 1M context, frontier reasoning, newest model (verified: ~13.1s API latency via real Telegram test).
3. **OpenRouter free**: `poolside/laguna-s-2.1:free` — agentic coding (Terminal-Bench 70.2%, DeepSWE 40.4%).
4. **OpenRouter free**: `nvidia/nemotron-3-super-120b-a12b:free` — multi-token prediction, high accuracy (AIME 2025 / SWE-Bench Verified).
5. **OpenRouter free**: `cohere/north-mini-code:free` — JSON schema tool use, 256K ctx / 64K out.
6. **OpenRouter free**: `openai/gpt-oss-20b:free` — function calling, structured outputs.
7. **OpenRouter free**: `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free` — multimodal (text/image/video/audio).
8. **OpenRouter free**: `google/gemma-4-26b-a4b-it:free` — native function calling (may hit Google upstream 429 at peak times).
9. **Nous Portal free #1**: `upstage/solar-pro4:free` — 524K context, best for long agentic runs (verified: replied in ~9.6s through the real Telegram fallback test).
10. **Nous Portal free #2**: `tencent/hy3:free` — 295B MoE, 262K context, agentic/tool workflows (verified: ~6.1s).
11. **Nous Portal free #3**: `stepfun/step-3.7-flash:free` — multimodal + reasoning (verified: ~7.8s).
12. **Gemini** (native API): `gemini-3.6-flash` — uses `GEMINI_API_KEY` from `shared\hermes_home\.env`. Until the key is set, Hermes automatically skips to the free tiers above (verified: fallback entries without keys are skipped).

> ⚠️ **LM Studio tiers removed (17 Aug 2026, Workthrough v12):** the old tiers ⑬⑭ (work PC via Tailscale `qwen/qwen3.5-9b` and this machine's `qwen/qwen3-1.7b`) plus the `custom_providers` entries were **removed** — the system is now API-only (OpenRouter + Nous + Gemini). No LM Studio / Tailscale / work-PC dependency remains; `lmstudio-alert.py`, `lmstudio-watch.ps1` and `HermesLMStudioWatch` are deleted. History of why (CPU-only too slow, RAM pressure) is preserved in Workthrough §14 v8–v10.

> 💡 Nous Portal free models only work via the `nous` provider (OAuth login once: `hermes auth add nous`); paid models (e.g. `anthropic/claude-sonnet-4.6`) return `requires credits` until you top up at portal.nousresearch.com.

Change them in `shared\hermes_home\config.yaml` only after verifying model availability at `https://openrouter.ai/api/v1/models` (Nous: `inference-api.nousresearch.com/v1/models`).

## Current scope and next integrations

**Working now, 100% free:** product workspaces, the two-phase build → review → publish flow, per-platform publishing tracking, promo scripts, promo videos (ffmpeg) with Thai/English voiceover (edge-tts), auto-downloaded product photos, and the full button-driven Telegram flow.

**Still placeholders (need real adapters/keys):** Shopee product search (awaiting Affiliate API keys + whitelist), live posting to YouTube/TikTok/Facebook, and EPUB/PDF publishing. Add and test one integration at a time, starting with the Shopee Affiliate API so researched product data flows in automatically.
