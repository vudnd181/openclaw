#!/bin/bash
set -euo pipefail

# deploy-bot.sh — Deploy a new OpenClaw bot instance
# Usage: ./deploy-bot.sh <bot_name> [model]
# Example: ./deploy-bot.sh alice
# Example: ./deploy-bot.sh alice claude-opus-4.6
#
# Telegram token and chat IDs can be configured later via the web UI.
# The Claudible API key is read from CLAUDIBLE_API_KEY in .env (shared by all bots).
# Available models: claude-haiku-4.5, claude-sonnet-4.6 (default), claude-opus-4.6

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOTS_DIR="$SCRIPT_DIR/bots"
PORT_REGISTRY="$BOTS_DIR/.port-registry"
TEMPLATE="$SCRIPT_DIR/config.bot.template.json"
BASE_PORT=18789

VALID_MODELS=("claude-haiku-4.5" "claude-sonnet-4.6" "claude-opus-4.6")
DEFAULT_MODEL="claude-sonnet-4.6"

# --- Argument Parsing ---
BOT_NAME="${1:-}"
MODEL="${2:-$DEFAULT_MODEL}"
TELEGRAM_TOKEN=""
CHAT_IDS=""

if [ -z "$BOT_NAME" ]; then
    echo "Usage: ./deploy-bot.sh <bot_name> [model]"
    echo ""
    echo "Examples:"
    echo "  ./deploy-bot.sh alice"
    echo "  ./deploy-bot.sh alice claude-opus-4.6"
    echo ""
    echo "Available models: ${VALID_MODELS[*]}"
    echo "Default model: $DEFAULT_MODEL"
    echo ""
    echo "Telegram token and channels can be configured later via the web UI."
    exit 1
fi

# --- Validate bot name ---
if [[ ! "$BOT_NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    echo "❌ Bot name must be lowercase alphanumeric with optional hyphens (e.g., 'alice', 'support-bot')"
    exit 1
fi

# --- Validate model ---
MODEL_VALID=false
for m in "${VALID_MODELS[@]}"; do
    if [ "$MODEL" = "$m" ]; then MODEL_VALID=true; break; fi
done
if [ "$MODEL_VALID" = false ]; then
    echo "❌ Invalid model: $MODEL"
    echo "   Available models: ${VALID_MODELS[*]}"
    exit 1
fi

# --- Check template exists ---
if [ ! -f "$TEMPLATE" ]; then
    echo "❌ Template not found: $TEMPLATE"
    exit 1
fi

# --- Read shared API key from .env ---
if [ -f "$SCRIPT_DIR/.env" ]; then
    CLAUDIBLE_KEY=$(grep '^CLAUDIBLE_API_KEY=' "$SCRIPT_DIR/.env" | cut -d'=' -f2-)
fi

if [ -z "${CLAUDIBLE_KEY:-}" ]; then
    echo "❌ CLAUDIBLE_API_KEY not found in .env"
    echo "   Add this line to .env:"
    echo "   CLAUDIBLE_API_KEY=your-api-key-here"
    exit 1
fi

# --- Check for duplicate ---
if [ -d "$BOTS_DIR/$BOT_NAME" ]; then
    echo "❌ Bot '$BOT_NAME' already exists at bots/$BOT_NAME/"
    exit 1
fi

# --- Assign port offset ---
mkdir -p "$BOTS_DIR"
touch "$PORT_REGISTRY"

# Find the next available offset (fill gaps from removed bots)
USED_OFFSETS=$(awk '{print $2}' "$PORT_REGISTRY" | sort -n)
NEXT_OFFSET=1
for offset in $USED_OFFSETS; do
    if [ "$offset" -eq "$NEXT_OFFSET" ]; then
        NEXT_OFFSET=$((NEXT_OFFSET + 1))
    else
        break
    fi
done

EXTERNAL_PORT=$((BASE_PORT + NEXT_OFFSET - 1))

# --- Create bot directory ---
mkdir -p "$BOTS_DIR/$BOT_NAME"

# --- Generate config.json from template ---
SECRET_TOKEN=$(openssl rand -hex 32)

# Build allowFrom JSON: empty → [] or ["id1","id2"]
if [ -z "$CHAT_IDS" ]; then
    ALLOW_FROM_JSON='[]'
    ALLOW_FROM_REPLACEMENT='[]'
else
    ALLOW_FROM_IDS=$(echo "$CHAT_IDS" | sed 's/,/","/g')
    ALLOW_FROM_JSON='"'"$ALLOW_FROM_IDS"'"'
    ALLOW_FROM_REPLACEMENT='["'"$ALLOW_FROM_IDS"'"]'
fi

sed -e "s|YOUR_TELEGRAM_BOT_TOKEN|${TELEGRAM_TOKEN}|g" \
    -e "s|YOUR_CLAUDIBLE_API_KEY|${CLAUDIBLE_KEY}|g" \
    -e "s|YOUR_SECRET_TOKEN|${SECRET_TOKEN}|g" \
    -e "s|\[\"ALLOWED_CHAT_IDS\"\]|${ALLOW_FROM_REPLACEMENT}|g" \
    -e "s|SELECTED_MODEL|${MODEL}|g" \
    "$TEMPLATE" > "$BOTS_DIR/$BOT_NAME/config.json"

# --- Inject bot's domain into allowedOrigins ---
NGINX_ENV_FILE="$SCRIPT_DIR/../nginx/.env"
if [ -f "$NGINX_ENV_FILE" ]; then
    BOT_DOMAIN=$(grep '^DOMAIN=' "$NGINX_ENV_FILE" | cut -d'=' -f2-)
fi
if [ -n "${BOT_DOMAIN:-}" ]; then
    # Add the bot's HTTPS origin to allowedOrigins in the config
    sed -i "s|\"allowedOrigins\": \[\"http://localhost:18789\"\]|\"allowedOrigins\": [\"http://localhost:18789\", \"https://${BOT_NAME}.${BOT_DOMAIN}\"]|" \
        "$BOTS_DIR/$BOT_NAME/config.json"
fi

echo "✅ Generated bots/$BOT_NAME/config.json (model: $MODEL)"

# --- Register port ---
echo "$BOT_NAME $NEXT_OFFSET" >> "$PORT_REGISTRY"
echo "✅ Registered port offset $NEXT_OFFSET (external port: $EXTERNAL_PORT)"

# --- Update .env ---
ENV_VAR_SUFFIX=$(echo "$BOT_NAME" | tr '[:lower:]-' '[:upper:]_')
cat >> "$SCRIPT_DIR/.env" << EOF

# Bot: $BOT_NAME
TOKEN_${ENV_VAR_SUFFIX}=${TELEGRAM_TOKEN}
EOF
echo "✅ Added TOKEN_${ENV_VAR_SUFFIX} to .env"

# --- Regenerate docker-compose.yml ---
"$SCRIPT_DIR/generate-compose.sh"

# --- Build and start ONLY this bot (--no-deps prevents touching other bots) ---
docker compose -f "$SCRIPT_DIR/docker-compose.yml" build "openclaw-bot-${BOT_NAME}"
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d --no-deps "openclaw-bot-${BOT_NAME}"

# --- Reload nginx to pick up new bot config ---
NGINX_ENV="$SCRIPT_DIR/../nginx/.env"
if [ -f "$NGINX_ENV" ]; then
    DEPLOY_DOMAIN=$(grep '^DOMAIN=' "$NGINX_ENV" | cut -d'=' -f2-)
fi
DEPLOY_DOMAIN="${DEPLOY_DOMAIN:-}"

NGINX_CONTAINER="bot-nginx"
if docker ps --format '{{.Names}}' | grep -q "^${NGINX_CONTAINER}$"; then
    if docker exec "$NGINX_CONTAINER" nginx -t 2>/dev/null; then
        docker exec "$NGINX_CONTAINER" nginx -s reload
        echo "✅ Nginx reloaded with config for ${BOT_NAME}.${DEPLOY_DOMAIN}"
    else
        echo "⚠️  Nginx config test failed. Check nginx/conf.d/${BOT_NAME}.conf"
        echo "   Run: docker exec $NGINX_CONTAINER nginx -t"
    fi
else
    echo "ℹ️  Nginx not running. Start it with: cd ../nginx && docker compose up -d"
fi

echo ""
echo "🚀 Bot '$BOT_NAME' is now running!"
echo "   Container:  openclaw-bot-${BOT_NAME}"
echo "   Model:      claudible/${MODEL}"
echo "   Port:       $EXTERNAL_PORT → 18789 (internal)"
if [ -n "$DEPLOY_DOMAIN" ]; then
    echo "   Dashboard:  https://${BOT_NAME}.${DEPLOY_DOMAIN}"
fi
echo "   Config:     bots/$BOT_NAME/config.json"
echo ""
echo "📋 View logs: docker compose logs -f openclaw-bot-${BOT_NAME}"

# --- Wait for bot to be healthy, then start auto-approve ---
echo ""
echo "⏳ Waiting for bot to start (health check)..."
HEALTH_TIMEOUT=30
HEALTH_ELAPSED=0
while [ "$HEALTH_ELAPSED" -lt "$HEALTH_TIMEOUT" ]; do
    if docker exec "openclaw-bot-${BOT_NAME}" curl -sf http://localhost:18789/health &>/dev/null; then
        echo "✅ Bot is healthy!"
        break
    fi
    sleep 2
    HEALTH_ELAPSED=$((HEALTH_ELAPSED + 2))
done

if [ "$HEALTH_ELAPSED" -ge "$HEALTH_TIMEOUT" ]; then
    echo "⚠️  Bot not healthy yet. You can pair manually later:"
    echo "   ./auto-approve.sh $BOT_NAME --wait"
else
    echo ""
    echo "🔗 Open the dashboard in your browser, then device will be auto-approved."
    echo "   Starting auto-approve (60s timeout)..."
    echo ""
    "$SCRIPT_DIR/auto-approve.sh" "$BOT_NAME" --wait || true
fi
