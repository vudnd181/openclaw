#!/bin/bash
set -euo pipefail

# remove-bot.sh — Remove an OpenClaw bot instance
# Usage: ./remove-bot.sh <bot_name> [--keep-data] [--force]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOTS_DIR="$SCRIPT_DIR/bots"
PORT_REGISTRY="$BOTS_DIR/.port-registry"

BOT_NAME=""
KEEP_DATA=""
FORCE=""

for arg in "$@"; do
    case "$arg" in
        --keep-data) KEEP_DATA="--keep-data" ;;
        --force)     FORCE="--force" ;;
        -*)          echo "Unknown option: $arg"; exit 1 ;;
        *)           BOT_NAME="$arg" ;;
    esac
done

if [ -z "$BOT_NAME" ]; then
    echo "Usage: ./remove-bot.sh <bot_name> [--keep-data] [--force]"
    echo "  --keep-data  Keep the Docker volume (conversation history)"
    echo "  --force      Skip confirmation prompt (for API/automation use)"
    exit 1
fi

SERVICE_NAME="openclaw-bot-${BOT_NAME}"
ENV_VAR_SUFFIX=$(echo "$BOT_NAME" | tr '[:lower:]-' '[:upper:]_')

# --- Check bot exists ---
if [ ! -d "$BOTS_DIR/$BOT_NAME" ] && ! grep -q "^${BOT_NAME} " "$PORT_REGISTRY" 2>/dev/null; then
    echo "❌ Bot '$BOT_NAME' not found."
    exit 1
fi

# --- Confirm (skip with --force for API/automation use) ---
if [ "$FORCE" != "--force" ]; then
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
fi

# --- Stop and remove container ---
# 1. Try docker compose first (handles service defined in compose file)
docker compose -f "$SCRIPT_DIR/docker-compose.yml" stop "$SERVICE_NAME" 2>/dev/null || true
docker compose -f "$SCRIPT_DIR/docker-compose.yml" rm -f "$SERVICE_NAME" 2>/dev/null || true

# 2. Fallback: force-remove container directly by name (catches orphans / stuck containers)
if docker ps -a --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$"; then
    docker stop "$SERVICE_NAME" 2>/dev/null || true
    docker rm -f "$SERVICE_NAME" 2>/dev/null || true
    echo "✅ Force-removed lingering container: $SERVICE_NAME"
fi
echo "✅ Stopped and removed container"

# --- Remove volume ---
if [ "$KEEP_DATA" != "--keep-data" ]; then
    # Try all possible volume name formats (depends on compose project name)
    COMPOSE_PROJECT=$(basename "$SCRIPT_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
    docker volume rm "${COMPOSE_PROJECT}_${SERVICE_NAME}" 2>/dev/null || true
    docker volume rm "openclaw_docker_${SERVICE_NAME}" 2>/dev/null || true
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

# --- Reload nginx (stale config already removed by generate-compose.sh) ---
NGINX_ENV="$SCRIPT_DIR/../nginx/.env"
if [ -f "$NGINX_ENV" ]; then
    DEPLOY_DOMAIN=$(grep '^DOMAIN=' "$NGINX_ENV" | cut -d'=' -f2-)
fi
DEPLOY_DOMAIN="${DEPLOY_DOMAIN:-}"

NGINX_CONTAINER="bot-nginx"
if docker ps --format '{{.Names}}' | grep -q "^${NGINX_CONTAINER}$"; then
    if docker exec "$NGINX_CONTAINER" nginx -t 2>/dev/null; then
        docker exec "$NGINX_CONTAINER" nginx -s reload
        echo "✅ Nginx reloaded (removed ${BOT_NAME}.${DEPLOY_DOMAIN})"
    else
        echo "⚠️  Nginx config test failed after removal. Check manually:"
        echo "   docker exec $NGINX_CONTAINER nginx -t"
    fi
fi

echo ""
echo "🗑️  Bot '$BOT_NAME' has been removed."
