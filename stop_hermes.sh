#!/usr/bin/env bash
# =============================================================================
# stop_hermes.sh — Stop the running Hermes Agent Docker container
# =============================================================================
# Usage:
#   ./stop_hermes.sh                   # uses default container name hermes-agent
#   ./stop_hermes.sh [config-file]     # reads container name from config
#   ./stop_hermes.sh --name my-name    # explicit container name override
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[hermes]${NC} $*"; }
warn()  { echo -e "${YELLOW}[hermes]${NC} $*"; }
error() { echo -e "${RED}[hermes]${NC} $*" >&2; }

# ── Parse arguments ────────────────────────────────────────────────────────────
CONTAINER_NAME=""
CONFIG_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            CONTAINER_NAME="$2"; shift 2 ;;
        --name=*)
            CONTAINER_NAME="${1#--name=}"; shift ;;
        -*)
            error "Unknown flag: $1"; exit 1 ;;
        *)
            CONFIG_FILE="$1"; shift ;;
    esac
done

# ── Resolve container name ─────────────────────────────────────────────────────
if [[ -z "$CONTAINER_NAME" ]]; then
    # Try to read from config file
    if [[ -z "$CONFIG_FILE" ]]; then
        for candidate in hermes-config.yaml hermes-config.yml hermes-config.json; do
            if [[ -f "$candidate" ]]; then
                CONFIG_FILE="$candidate"
                break
            fi
        done
    fi

    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        CONTAINER_NAME=$(python3 - "$CONFIG_FILE" <<'PYEOF' 2>/dev/null
import sys, os, json
path = sys.argv[1]
ext = os.path.splitext(path)[1].lower()
with open(path) as f:
    try:
        import yaml
        cfg = yaml.safe_load(f)
    except ImportError:
        f.seek(0)
        cfg = json.load(f)
name = (cfg or {}).get("docker", {}).get("container_name", "")
print(name or "hermes-agent")
PYEOF
        )
        info "Read container name from config: ${CONFIG_FILE}"
    fi

    # Final fallback
    CONTAINER_NAME="${CONTAINER_NAME:-hermes-agent}"
fi

# ── Check if container exists ──────────────────────────────────────────────────
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    warn "Container '${CONTAINER_NAME}' is not running (or does not exist)."
    exit 0
fi

# ── Stop ───────────────────────────────────────────────────────────────────────
info "Stopping container '${CONTAINER_NAME}'…"
docker stop "${CONTAINER_NAME}"
info "Done."
