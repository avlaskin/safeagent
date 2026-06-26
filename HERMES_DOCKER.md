# Running Hermes Agent in Docker with Telegram & WhatsApp

Run [Hermes Agent](https://hermes-agent.nousresearch.com/) in Docker with
Telegram and/or WhatsApp gateway support. All configuration lives in a single
`hermes-config.yaml` file — no environment variables to juggle.

At least one messaging gateway (Telegram or WhatsApp) must be configured.
Both can run simultaneously against different numbers/bots.

---

## Files

| File | Purpose |
|---|---|
| `hermes-config.yaml` | All configuration (tokens, model, keys, Docker settings) |
| `run_hermes_config.sh` | Start the agent |
| `stop_hermes.sh` | Stop the agent |

---

## Step 1 — Set Up Your Messaging Gateway

### Option A — Telegram

1. Message [@BotFather](https://t.me/BotFather) on Telegram.
2. Send `/newbot` and follow the prompts (name + username ending in `bot`).
3. BotFather replies with a token like `123456789:ABCdefGHIjklMNOpqrSTUvwxYZ`. **Copy it.**
4. Find your numeric user ID by messaging [@userinfobot](https://t.me/userinfobot) — it returns a number like `987654321`. **Copy it.**

In `hermes-config.yaml`:
```yaml
telegram:
  bot_token: "123456789:ABCdefGHIjklMNOpqrSTUvwxYZ"
  allowed_users:
    - "987654321"
```

> **Security:** Never commit your bot token to version control.

### Option B — WhatsApp (Baileys bridge, personal account)

> **⚠️ First run only:** A QR code will appear in the terminal — scan it with
> WhatsApp on your phone (Settings → Linked Devices → Link a Device). The
> session is saved to `hermes-data/` and **subsequent restarts don't require
> rescanning**.

> **Note:** Uses your personal WhatsApp account via a third-party Baileys
> bridge (not the official Business API). Use a dedicated phone number for the
> bot to reduce risk of account restrictions.

In `hermes-config.yaml`:
```yaml
whatsapp:
  enabled: true
  mode: "bot"        # "bot" = dedicated number | "self-chat" = your own number
  allowed_users:
    - "15551234567"  # country code + number, NO leading '+'
```

Node.js v18+ is installed automatically inside the container — no action needed.

### Option C — Both simultaneously

Fill in both `telegram` and `whatsapp` sections. Both gateways start together
under the same `hermes gateway` process.

---

## Step 2 — Choose a Model

Edit the `model:` field in `hermes-config.yaml`.

**Gemini (Google AI Studio)** — get a key at <https://aistudio.google.com/app/apikey>

| Model | `model:` value | Status | Notes |
|---|---|---|---|
| Gemini 3.5 Flash | `google:gemini-3.5-flash` | ✅ Stable | Best for agentic/coding — recommended default |
| Gemini 3.1 Flash-Lite | `google:gemini-3.1-flash-lite` | ✅ Stable | Fastest & cheapest |
| Gemini 3.1 Pro | `google:gemini-3.1-pro` | 🔬 Preview | Flagship reasoning, 2M token context |
| Gemini 2.5 Flash | `google:gemini-2.5-flash` | ✅ Stable | Previous gen, still excellent |
| Gemini 2.5 Pro | `google:gemini-2.5-pro` | ✅ Stable | Most advanced 2.5 model |

> **⚠️** `gemini-2.0-flash` was shut down June 1, 2026 — use `gemini-2.5-flash` or newer.

**Local model (LM Studio / Ollama)**

```yaml
model: "lmstudio:your-model-name"
local_model:
  base_url: "http://host.docker.internal:1234/v1"
```

**OpenRouter** (200+ models)

```yaml
model: "openrouter:google/gemini-2.5-flash-preview"
api_keys:
  openrouter: "sk-or-..."
```

**OpenAI**

```yaml
model: "openai:gpt-4o"
api_keys:
  openai: "sk-..."
```

---

## Step 3 — Start

```bash
chmod +x run_hermes_config.sh stop_hermes.sh   # first time only
./run_hermes_config.sh
```

On first run the script will:
1. Pull `python:3.12-slim`.
2. Install Node.js 20 (for the WhatsApp Baileys bridge).
3. Install `hermes-agent` with messaging, Google and web extras.
4. Install Chromium (for web browsing tools) — ~400 MB, downloaded once.
5. Write `~/.hermes/.env` inside the container from your config.
6. Start `hermes gateway` — your bot(s) come online within seconds.
   - If WhatsApp is enabled and has no saved session, a QR code appears now.

---

## Step 4 — Stop

```bash
./stop_hermes.sh
```

Or press `Ctrl-C` in the terminal where the agent is running.
Your data in `hermes-data/` is never affected.

---

## Config File Reference

```yaml
# hermes-config.yaml

# ── Messaging (at least one required) ──────────────────────────────────────────
telegram:
  bot_token: ""          # from @BotFather — leave empty to disable
  allowed_users:
    - ""                 # numeric Telegram user IDs

whatsapp:
  enabled: false         # set to true to enable
  mode: "bot"            # "bot" or "self-chat"
  allowed_users:
    - ""                 # phone numbers: country code + number, no '+'
                         # use "*" to allow everyone

# ── Model (required) ───────────────────────────────────────────────────────────
model: "google:gemini-3.5-flash"

# ── API Keys ───────────────────────────────────────────────────────────────────
api_keys:
  google: ""             # Google AI Studio key
  openai: ""
  openrouter: ""
  anthropic: ""

# ── Local model (optional) ─────────────────────────────────────────────────────
local_model:
  base_url: ""           # e.g. http://host.docker.internal:1234/v1
  ollama_url: ""         # e.g. http://host.docker.internal:11434/v1

# ── Docker ─────────────────────────────────────────────────────────────────────
docker:
  container_name: "hermes-agent"
  data_dir: "./hermes-data"        # persists memories, skills, WhatsApp session
  image: "python:3.12-slim"
```

---

## Persistent Data

The `data_dir` folder (default `./hermes-data`) is mounted into the container
at `/root/.hermes`. Everything persists here across restarts:

- Conversation memories and agent skills
- Chromium browser profile
- **WhatsApp session** (`hermes-data/platforms/whatsapp/session`) — no QR rescan needed after the first time

Back it up with `cp -r hermes-data hermes-data.bak`.

---

## Switching Models

Edit `model:` in `hermes-config.yaml` and restart:

```bash
./stop_hermes.sh && ./run_hermes_config.sh
```

You can also switch mid-conversation from either chat platform with `/model google:gemini-3.1-pro`.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Bot doesn't reply (Telegram) | `telegram.allowed_users` must contain your **numeric** user ID (not username) |
| Bot doesn't reply (WhatsApp) | `whatsapp.allowed_users` must use country code + number without `+` (e.g. `15551234567`) |
| WhatsApp QR code appears on every restart | The `hermes-data/` volume was deleted — session is gone, rescan required |
| WhatsApp stops working after an update | WhatsApp updated their Web protocol — pull latest hermes and re-pair: `hermes whatsapp` inside the container |
| Bad Gateway on Telegram startup | DNS issue — the scripts set `--dns 8.8.8.8` automatically; should self-resolve |
| Local model unreachable | Ensure LM Studio / Ollama is running on the host; use `host.docker.internal` |
| Container exits immediately | Remove `--rm` temporarily and run `docker logs hermes-agent` |
| Gemini quota errors | Switch to `google:gemini-3.5-flash` or `google:gemini-2.5-flash` (generous free tiers) |
| PyYAML not installed | `pip install pyyaml` on the host (needed to parse the YAML config) |

---

## Common Telegram Commands

| Command | What it does |
|---|---|
| `/new` | Start a fresh conversation |
| `/model google:gemini-3.1-pro` | Switch model without restarting |
| `/status` | Show current model and session info |
| `/stop` | Interrupt a running task |
| `/help` | List all available commands |
