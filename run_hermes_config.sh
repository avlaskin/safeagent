#!/usr/bin/env bash
# =============================================================================
# run_hermes_config.sh — Launch Hermes Agent in Docker using a config file
# =============================================================================
# Usage:
#   ./run_hermes_config.sh [config-file]
#
# If config-file is omitted, looks for hermes-config.yaml or hermes-config.json
# in the current directory.
#
# Supported formats: YAML (.yaml / .yml) and JSON (.json)
#
# Generate a template config:
#   ./run_hermes_config.sh --init
# =============================================================================

set -euo pipefail

# ── Colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[hermes]${NC} $*"; }
warn()  { echo -e "${YELLOW}[hermes]${NC} $*"; }
error() { echo -e "${RED}[hermes]${NC} $*" >&2; }
step()  { echo -e "${CYAN}[hermes]${NC} $*"; }

# ── --init: write a template config and exit ───────────────────────────────────
if [[ "${1:-}" == "--init" ]]; then
    DEST="${2:-hermes-config.yaml}"
    if [[ -f "$DEST" ]]; then
        error "File already exists: $DEST  (use a different name or remove it first)"
        exit 1
    fi
    cat > "$DEST" <<'TEMPLATE'
# hermes-config.yaml — fill in your values and run:
#   ./run_hermes_config.sh

telegram:
  bot_token: ""          # from @BotFather on Telegram
  allowed_users:
    - ""                 # your numeric Telegram user ID (@userinfobot)

model: "google:gemini-3.5-flash"
# Other examples:
#   google:gemini-3.1-pro          (preview, best reasoning)
#   google:gemini-2.5-flash        (previous gen, still great)
#   lmstudio:your-model-name       (local LM Studio)
#   ollama:llama3                  (local Ollama)
#   openrouter:google/gemini-2.5-flash-preview
#   openai:gpt-4o

api_keys:
  google: ""       # https://aistudio.google.com/app/apikey
  openai: ""       # https://platform.openai.com/api-keys
  openrouter: ""   # https://openrouter.ai/keys
  anthropic: ""    # https://console.anthropic.com/

local_model:
  base_url: "http://host.docker.internal:1234/v1"
  ollama_url: ""

docker:
  container_name: "hermes-agent"
  data_dir: "./hermes-data"
  image: "python:3.12-slim"
TEMPLATE
    info "Template written to: $DEST"
    info "Edit it, then run:  ./run_hermes_config.sh $DEST"
    exit 0
fi

# ── Locate config file ─────────────────────────────────────────────────────────
CONFIG_FILE=""
if [[ -n "${1:-}" ]]; then
    CONFIG_FILE="$1"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
else
    for candidate in hermes-config.yaml hermes-config.yml hermes-config.json; do
        if [[ -f "$candidate" ]]; then
            CONFIG_FILE="$candidate"
            break
        fi
    done
    if [[ -z "$CONFIG_FILE" ]]; then
        error "No config file found. Looked for: hermes-config.yaml, hermes-config.yml, hermes-config.json"
        echo ""
        echo "  Create a template with:"
        echo "    ./run_hermes_config.sh --init"
        exit 1
    fi
fi

info "Using config: $CONFIG_FILE"

# ── Require python3 ────────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    error "python3 is required to parse the config file but was not found in PATH"
    exit 1
fi

# ── Parse config with Python (handles both YAML and JSON) ─────────────────────
# Outputs KEY=VALUE pairs that are eval'd into the shell.
# Falls back to json stdlib if PyYAML is not installed and the file is YAML.
PARSED=$(python3 - "$CONFIG_FILE" <<'PYEOF'
import sys, os, json

config_path = sys.argv[1]
ext = os.path.splitext(config_path)[1].lower()

def load_config(path, ext):
    with open(path) as f:
        if ext == ".json":
            return json.load(f)
        # Try PyYAML first
        try:
            import yaml
            return yaml.safe_load(f)
        except ImportError:
            pass
        # Fallback: try json anyway (some .yaml files are valid JSON supersets)
        try:
            f.seek(0)
            return json.load(f)
        except json.JSONDecodeError:
            print("ERROR: PyYAML is not installed and the config is not valid JSON.", file=sys.stderr)
            print("       Install it with:  pip install pyyaml", file=sys.stderr)
            print("       Or use a .json config file instead.", file=sys.stderr)
            sys.exit(1)

cfg = load_config(config_path, ext)

def get(d, *keys, default=""):
    """Nested dict lookup with a default."""
    for k in keys:
        if not isinstance(d, dict):
            return default
        d = d.get(k, default)
    return d if d is not None else default

def coerce_list(val):
    """Accept a list or comma-separated string; return comma-separated string."""
    if isinstance(val, list):
        return ",".join(str(v).strip() for v in val if str(v).strip())
    return str(val).strip() if val else ""

errors = []

# ── Telegram
bot_token     = get(cfg, "telegram", "bot_token")
tg_users_raw  = coerce_list(get(cfg, "telegram", "allowed_users"))
cleaned_tg    = [u for u in tg_users_raw.split(",") if u.strip() and u.strip() not in ('""', "''")]
telegram_ok   = bool(bot_token and cleaned_tg)

# ── WhatsApp
wa_enabled    = str(get(cfg, "whatsapp", "enabled", default="false")).lower() in ("true", "1", "yes")
wa_mode       = get(cfg, "whatsapp", "mode", default="bot")
wa_users_raw  = coerce_list(get(cfg, "whatsapp", "allowed_users"))
cleaned_wa    = [u for u in wa_users_raw.split(",") if u.strip() and u.strip() not in ('""', "''")]
whatsapp_ok   = bool(wa_enabled)

# ── Model
model         = get(cfg, "model")

if not telegram_ok and not whatsapp_ok:
    errors.append("At least one gateway must be configured:")
    errors.append("  • Telegram: set telegram.bot_token and telegram.allowed_users")
    errors.append("  • WhatsApp: set whatsapp.enabled: true and whatsapp.allowed_users")
if not model:
    errors.append("model is required")

# Per-gateway validation (only when that gateway is intended to be active)
if bot_token and not cleaned_tg:
    errors.append("telegram.bot_token is set but telegram.allowed_users has no valid IDs")
if wa_enabled and not cleaned_wa:
    errors.append("whatsapp.enabled is true but whatsapp.allowed_users has no valid phone numbers")

if errors:
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(2)

google_key     = get(cfg, "api_keys", "google")
openai_key     = get(cfg, "api_keys", "openai")
openrouter_key = get(cfg, "api_keys", "openrouter")
anthropic_key  = get(cfg, "api_keys", "anthropic")
lm_base_url    = get(cfg, "local_model", "base_url")  # empty string if not set
ollama_url     = get(cfg, "local_model", "ollama_url")
container_name = get(cfg, "docker", "container_name", default="hermes-agent")
data_dir       = get(cfg, "docker", "data_dir", default="./hermes-data")
image          = get(cfg, "docker", "image", default="python:3.12-slim")

# Emit as shell assignments (values are single-quoted; single quotes inside
# values are escaped by ending the quote, inserting \', and reopening).
def shell_quote(s):
    return "'" + str(s).replace("'", "'\\''") + "'"

vars = [
    # Telegram (empty string when not configured)
    ("TELEGRAM_BOT_TOKEN",     bot_token),
    ("TELEGRAM_ALLOWED_USERS", ",".join(cleaned_tg)),
    # WhatsApp
    ("WHATSAPP_ENABLED",       "true" if wa_enabled else ""),
    ("WHATSAPP_MODE",          wa_mode if wa_enabled else ""),
    ("WHATSAPP_ALLOWED_USERS", ",".join(cleaned_wa) if wa_enabled else ""),
    # Common
    ("HERMES_MODEL",           model),
    ("GOOGLE_API_KEY",         google_key),
    ("OPENAI_API_KEY",         openai_key),
    ("OPENROUTER_API_KEY",     openrouter_key),
    ("ANTHROPIC_API_KEY",      anthropic_key),
    ("LM_BASE_URL",            lm_base_url),
    ("OLLAMA_BASE_URL",        ollama_url),
    ("CONTAINER_NAME",         container_name),
    ("HERMES_DATA_DIR",        data_dir),
    ("DOCKER_IMAGE",           image),
]

for name, val in vars:
    print(f"{name}={shell_quote(val)}")
PYEOF
)

if [[ $? -ne 0 ]]; then
    # Python already printed the error
    exit 1
fi

# Load parsed values into current shell
eval "$PARSED"

# ── Resolve HERMES_DATA_DIR to absolute path ───────────────────────────────────
# Relative paths in the config are relative to the config file's directory.
CONFIG_DIR="$(cd "$(dirname "$CONFIG_FILE")" && pwd)"
if [[ "${HERMES_DATA_DIR}" != /* ]]; then
    HERMES_DATA_DIR="${CONFIG_DIR}/${HERMES_DATA_DIR}"
fi

# ── Prepare persistent data directory ─────────────────────────────────────────
mkdir -p "${HERMES_DATA_DIR}"

# ── Remove any stale container with the same name ─────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    warn "Removing existing container '${CONTAINER_NAME}'…"
    docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

# ── Build docker run arguments ─────────────────────────────────────────────────
DOCKER_ARGS=(
    --name "${CONTAINER_NAME}"
    --rm
    --interactive
    --tty

    # Explicit bridge network + public DNS so the container can reach
    # api.telegram.org. Without this, the bridge network inherits the host's
    # /etc/resolv.conf which may contain 127.0.0.1 — unreachable from inside
    # the container — causing "Bad Gateway" / DNS resolution failures.
    --network bridge
    --dns 8.8.8.8
    --dns 8.8.4.4

    -v "${HERMES_DATA_DIR}:/root/.hermes"
    --add-host "host.docker.internal:host-gateway"

    # Required — always passed (may be empty string if gateway not used)
    -e "TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}"
    -e "TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS}"
    -e "HERMES_MODEL=${HERMES_MODEL}"
)

# WhatsApp — only injected when enabled
if [[ -n "${WHATSAPP_ENABLED:-}" ]]; then
    DOCKER_ARGS+=(
        -e "WHATSAPP_ENABLED=${WHATSAPP_ENABLED}"
        -e "WHATSAPP_MODE=${WHATSAPP_MODE:-bot}"
        -e "WHATSAPP_ALLOWED_USERS=${WHATSAPP_ALLOWED_USERS}"
    )
fi

# Optional: local model URL — only injected when explicitly configured
if [[ -n "${LM_BASE_URL:-}" ]]; then
    DOCKER_ARGS+=(
        -e "LM_BASE_URL=${LM_BASE_URL}"
        -e "OPENAI_BASE_URL=${LM_BASE_URL}"
    )
fi

# Optional API keys — only passed when non-empty
[[ -n "${GOOGLE_API_KEY:-}"     ]] && DOCKER_ARGS+=(-e "GOOGLE_API_KEY=${GOOGLE_API_KEY}")
[[ -n "${OPENAI_API_KEY:-}"     ]] && DOCKER_ARGS+=(-e "OPENAI_API_KEY=${OPENAI_API_KEY}")
[[ -n "${OPENROUTER_API_KEY:-}" ]] && DOCKER_ARGS+=(-e "OPENROUTER_API_KEY=${OPENROUTER_API_KEY}")
[[ -n "${ANTHROPIC_API_KEY:-}"  ]] && DOCKER_ARGS+=(-e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")
[[ -n "${OLLAMA_BASE_URL:-}"    ]] && DOCKER_ARGS+=(-e "OLLAMA_BASE_URL=${OLLAMA_BASE_URL}")

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
info "Starting Hermes Agent"
info "  Config    : ${CONFIG_FILE}"
info "  Container : ${CONTAINER_NAME}"
info "  Image     : ${DOCKER_IMAGE}"
info "  Model     : ${HERMES_MODEL}"
[[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] && info "  Telegram  : users=${TELEGRAM_ALLOWED_USERS}"
[[ -n "${WHATSAPP_ENABLED:-}"   ]] && info "  WhatsApp  : mode=${WHATSAPP_MODE:-bot}  users=${WHATSAPP_ALLOWED_USERS}"
info "  Data dir  : ${HERMES_DATA_DIR}"
echo ""

# ── Run ────────────────────────────────────────────────────────────────────────
exec docker run "${DOCKER_ARGS[@]}" \
    "${DOCKER_IMAGE}" \
    bash -c '
        set -euo pipefail

        echo "[setup] Installing system dependencies…"
        # Node.js v18+ is required by the WhatsApp Baileys bridge.
        DEBIAN_FRONTEND=noninteractive apt-get update -qq \
            && apt-get install -y -qq --no-install-recommends curl git nodejs npm > /dev/null 2>&1
        # Upgrade to Node 18 if apt provided an older version
        node_major=$(node --version 2>/dev/null | cut -d. -f1 | tr -dc '0-9' || echo 0)
        if [[ "${node_major}" -lt 18 ]]; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs > /dev/null 2>&1
        fi

        echo "[setup] Installing hermes-agent with messaging extras…"
        pip install --quiet --upgrade pip
        pip install --quiet "hermes-agent[messaging,google,cli,web]"
        pip install --quiet playwright   # ensure playwright module is present

        echo "[setup] Installing Chromium browser for web tools…"
        DEBIAN_FRONTEND=noninteractive python -m playwright install --with-deps chromium
        echo "[setup] Chromium installed."

        echo "[setup] Writing ~/.hermes/.env from environment…"
        mkdir -p /root/.hermes
        cat > /root/.hermes/.env <<ENV
# Auto-generated by run_hermes_config.sh — do not edit manually
${TELEGRAM_BOT_TOKEN:+TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}}
${TELEGRAM_ALLOWED_USERS:+TELEGRAM_ALLOWED_USERS=${TELEGRAM_ALLOWED_USERS}}
${WHATSAPP_ENABLED:+WHATSAPP_ENABLED=${WHATSAPP_ENABLED}}
${WHATSAPP_MODE:+WHATSAPP_MODE=${WHATSAPP_MODE}}
${WHATSAPP_ALLOWED_USERS:+WHATSAPP_ALLOWED_USERS=${WHATSAPP_ALLOWED_USERS}}
HERMES_MODEL=${HERMES_MODEL}
${LM_BASE_URL:+LM_BASE_URL=${LM_BASE_URL}}
${LM_BASE_URL:+OPENAI_BASE_URL=${LM_BASE_URL}}
${GOOGLE_API_KEY:+GOOGLE_API_KEY=${GOOGLE_API_KEY}}
${OPENAI_API_KEY:+OPENAI_API_KEY=${OPENAI_API_KEY}}
${OPENROUTER_API_KEY:+OPENROUTER_API_KEY=${OPENROUTER_API_KEY}}
${ANTHROPIC_API_KEY:+ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}}
${OLLAMA_BASE_URL:+OLLAMA_BASE_URL=${OLLAMA_BASE_URL}}
ENV

        echo "[setup] Done. Starting Hermes gateway…"
        echo ""
        exec hermes gateway
    '
