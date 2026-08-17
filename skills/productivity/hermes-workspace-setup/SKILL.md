---
name: hermes-workspace-setup
description: "Set up Hermes workspaces: task folders, HERMES_HOME layout, gateway lifecycle, fallback model chain, cross-machine local AI over Tailscale, and the hermes-shared repo sync workflow."
category: productivity
version: 1.1.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [hermes, workspace, gateway, fallback, config, tailscale, lm-studio, sync]
    related_skills: [windows-service-management, systematic-debugging]
---

## When to Use

- You want to start a new task with Hermes Agent and keep its files/notes/artifacts isolated in a dedicated folder under a workspace root.
- You need to (re)configure a Hermes agent workspace: check/repair the gateway, edit the model fallback chain, wire a machine to use another machine's local AI over Tailscale, or sync skills/scripts through the `hermes-shared` GitHub repo.

## Part A — Per-task workspace folders (generic)

1. **Choose a workspace root** (common: `~/Documents/ProjectByHermes`, i.e. `%USERPROFILE%\Documents\ProjectByHermes`).
2. **Ensure the root exists**: `mkdir -p "$HOME/Documents/ProjectByHermes"`.
3. **Create a task subfolder** — slugify the task title (lowercase, spaces → hyphens, strip specials):
   ```bash
   TASK_NAME="Create a web scraper for news"
   SLUG=$(echo "$TASK_NAME" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | sed 's/[^a-z0-9-]//g')
   mkdir -p "$HOME/Documents/ProjectByHermes/$SLUG"
   ```
4. **Set the working directory** for subsequent Hermes tool calls (terminal, file ops) to this subfolder.
5. Proceed with the task; all created files land inside the task folder unless you specify another path.

**Pitfalls:** forgetting to slugify → spaces/specials break scripts; reusing a task name may overwrite previous work (append a timestamp); on Windows use Git Bash or PowerShell equivalents for the mkdir commands.

## Part B — HERMES_HOME layout (the real workspace root)

`HERMES_HOME` is the root of everything for the gateway. On this setup it is `C:\AI_FACTORY\shared\hermes_home` (the guide documents `C:\AI Factory` as the default; always confirm with `echo $env:HERMES_HOME`).

```
$HERMES_HOME\
├── config.yaml        ← provider + fallback chain (PER-MACHINE, never push)
├── .env               ← API tokens (GEMINI, OPENROUTER, TELEGRAM...) (never push)
├── auth.json          ← OAuth credentials, e.g. Nous portal (never push)
├── skills\            ← installed skills (bundled + local, synced from hermes-shared)
├── logs\              ← agent.log, gateway.log, watchdog.log, errors.log
├── state\             ← gateway.lifecycle.json, gateway.pid, gateway.heartbeat
├── gateway_state.json ← runtime status (Telegram connected?)
└── shared\tools\      ← ops scripts (start/stop gateway, watchdog, autostart)
```

## Part C — Gateway lifecycle

- Runs via Task Scheduler `AI_Factory_Gateway` (at logon) → hidden VBS → `start_gateway.bat` watchdog loop → `hermes gateway`. (The repo's shared alternative uses `HermesGatewayWatch` + heartbeat checks.)
- **Restart:** `schtasks /end /tn "AI_Factory_Gateway"` then `schtasks /run /tn "AI_Factory_Gateway"` (Git Bash: prefix `export MSYS_NO_PATHCONV=1`).
- **Verify:** wait ~30–60s; `gateway_state.json` should show `running` + Telegram `connected`.
- Full detail in the `windows-service-management` skill.

## Part D — The fallback model chain (config.yaml)

The current production chain (all in `config.yaml` — `primary` + `fallback` list). **API-only since v12 (17 Aug 2026): LM Studio / Tailscale / work-PC tiers were removed** — see Workthrough §14 v12:

| # | Provider | Model | Notes |
|---|---|---|---|
| Primary | openrouter | `nvidia/nemotron-3-ultra-550b-a55b:free` | 1M context, agent orchestration |
| 1 | openrouter | `nvidia/nemotron-3.5-lightning:free` | 1M ctx, reasoning, newest |
| 2 | openrouter | `poolside/laguna-s-2.1:free` | agentic coding |
| 3 | openrouter | `nvidia/nemotron-3-super-120b-a12b:free` | MTP, accuracy |
| 4 | openrouter | `cohere/north-mini-code:free` | JSON tool use |
| 5 | openrouter | `openai/gpt-oss-20b:free` | function calling |
| 6 | openrouter | `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free` | multimodal |
| 7 | openrouter | `google/gemma-4-26b-a4b-it:free` | function calling |
| 8 | nous | `upstage/solar-pro4:free` | 524K context — best for long work |
| 9 | nous | `tencent/hy3:free` | 295B MoE, agentic, 262K context |
| 10 | nous | `stepfun/step-3.7-flash:free` | multimodal |
| 11 | gemini | `gemini-3.6-flash` | needs `GEMINI_API_KEY` in `.env` |

### Provider gotchas (learned the hard way)

1. **Nous portal**: login once with `hermes auth add nous` (OAuth). Only `:free` models are usable without credits — paid models error with `requires credits`. Free choices tested: `solar-pro4:free`, `hy3:free`, `step-3.7-flash:free`.
2. **Gemini** needs `GEMINI_API_KEY` in `shared\hermes_home\.env`; without a key Hermes skips the tier automatically.
3. **All tiers are remote APIs now** — no local server to keep running, no `custom_providers` entries, no Tailscale dependency. (History of the removed LM Studio tiers: Workthrough §14 v8–v10.)

### Verify the chain

```bash
export HERMES_HOME='C:/AI_FACTORY/shared/hermes_home'
"$LOCALAPPDATA/hermes/hermes-agent/venv/Scripts/hermes.exe" fallback list
```

## Part E — (removed in v12 — was "Cross-machine local AI over Tailscale")

> LM Studio tiers (work PC `qwen/qwen3.5-9b` via Tailscale + this machine's `qwen/qwen3-1.7b`) were **removed on 17 Aug 2026** — the system is API-only. Related files deleted: `lmstudio-watch.ps1`, `lmstudio-alert.py`, `lmstudio-start.ps1`, `work-lmstudio-autostart.ps1`, `home-use-work-local.ps1`, `setup-home-machine.ps1` + task `HermesLMStudioWatch`. See Workthrough §14 v12 for the reasoning.

## Part F — Sharing skills & scripts via hermes-shared

The GitHub repo `https://github.com/Seikomura/hermes-shared` is the single source of truth for skills, ops scripts and docs shared between machines.

```
repo (GitHub) = center
   ▲ push               │ pull + deploy (sync.ps1)
   │                    ▼
work machine ◄─────────► home machine
```

- **Sync to this machine:** `powershell -ExecutionPolicy Bypass -File sync.ps1 -Scripts`
  (git pull, copies `skills\` → `$HERMES_HOME\skills\`, `scripts\` → `$HERMES_HOME`, installs Task Scheduler tasks).
- **Push back accidental machine edits:** `sync.ps1 -Import` (copies `$HERMES_HOME\skills\windows-service-management` and `$HERMES_HOME\skills\productivity\hermes-workspace-setup` back into the repo), then commit + push.
- **Golden rules:**
  1. Edit skills/scripts **in the repo only**, never directly under `$HERMES_HOME\skills\` or `shared\tools\`.
  2. **Never push** `.env`, `auth.json`, `config.yaml`, logs, `*.db` — protected by `.gitignore` + `check-secrets.ps1` (installed as the pre-commit hook).
  3. Paths inside scripts (e.g. `C:\AI_FACTORY\...`, `100.77.88.33`) are machine-specific — adjust per machine after copying.
- After adding a skill to the repo + syncing, confirm it loads: `hermes skills list` (new skills appear as `local` / `enabled`).

## Quick diagnostic loop

1. `gateway_state.json` — running? Telegram connected?
2. `state\gateway.heartbeat` age — < 4 min?
3. `logs\gateway.log` / `logs\errors.log` tail — errors?
4. `hermes fallback list` — chain intact?
5. (Removed — no work-PC check needed since v12; the chain is API-only.)

See `docs\workthrough.md` (Hermes troubleshooting) and `docs\ai-factory-workthrough.md` §10.5 (how to read `agent.log` to find which tier answered a Telegram turn).
