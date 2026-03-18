#!/bin/bash
set -euo pipefail

# remove-bot.sh — Remove an OpenClaw bot instance
# Usage: ./remove-bot.sh <bot_name> [--keep-data]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOTS_DIR="$SCRIPT_DIR/bots"
PORT_REGISTRY="$BOTS_DIR/.port-registry"

BOT_NAME="${1:-}"
KEEP_DATA="${2:-}"

if [ -z "$BOT_NAME" ]; then
    echo "Usage: ./remove-bot.sh <bot_name> [--keep-data]"
    echo "  --keep-data  Keep the Docker volume (conversation history)"
    exit 1
fi

SERVICE_NAME="openclaw-bot-${BOT_NAME}"
ENV_VAR_SUFFIX=$(echo "$BOT_NAME" | tr '[:lower:]-' '[:upper:]_')

# --- Check bot exists ---
if [ ! -d "$BOTS_DIR/$BOT_NAME" ] && ! grep -q "^${BOT_NAME} " "$PORT_REGISTRY" 2>/dev/null; then
    echo "❌ Bot '$BOT_NAME' not found."
    exit 1
fi

# --- Confirm ---
echo "⚠️  This will remove bot '$BOT_NAME':"
echo "   - Stop and remove container: $SERVICE_NAME"
if [ "$KEEP_DATA" != "--keep-data" ]; then
    echo "   - Delete Docker volume: $SERVICE_NAME (conversation history)"
fi
echo "   - Delete bots/$BOT_NAME/ directory"
echo "   - Remove from .env and port registry"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# --- Stop and remove container ---
docker compose -f "$SCRIPT_DIR/docker-compose.yml" stop "$SERVICE_NAME" 2>/dev/null || true
docker compose -f "$SCRIPT_DIR/docker-compose.yml" rm -f "$SERVICE_NAME" 2>/dev/null || true
echo "✅ Stopped and removed container"

# --- Remove volume ---
if [ "$KEEP_DATA" != "--keep-data" ]; then
    docker volume rm "openclaw_docker_${SERVICE_NAME}" 2>/dev/null || \
    docker volume rm "${SERVICE_NAME}" 2>/dev/null || true
    echo "✅ Removed Docker volume"
fi

# --- Remove from port registry ---
if [ -f "$PORT_REGISTRY" ]; then
    grep -v "^${BOT_NAME} " "$PORT_REGISTRY" > "${PORT_REGISTRY}.tmp" || true
    mv "${PORT_REGISTRY}.tmp" "$PORT_REGISTRY"
fi
echo "✅ Removed from port registry"

# --- Remove bot directory ---
rm -rf "${BOTS_DIR:?}/$BOT_NAME"
echo "✅ Removed bots/$BOT_NAME/"

# --- Remove from .env ---
sed -i.bak "/^# Bot: ${BOT_NAME}$/d" "$SCRIPT_DIR/.env"
sed -i.bak "/^TOKEN_${ENV_VAR_SUFFIX}=/d" "$SCRIPT_DIR/.env"
rm -f "$SCRIPT_DIR/.env.bak"
echo "✅ Removed from .env"

# --- Regenerate docker-compose.yml ---
"$SCRIPT_DIR/generate-compose.sh"

echo ""
echo "🗑️  Bot '$BOT_NAME' has been removed."
