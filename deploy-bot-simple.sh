#!/bin/bash
set -euo pipefail

# deploy-bot-simple.sh — Deploy a new OpenClaw bot with no token required
# Usage: ./deploy-bot-simple.sh <bot_name> [model]
# Example: ./deploy-bot-simple.sh alice
# Example: ./deploy-bot-simple.sh alice claude-opus-4.6
#
# Telegram token and chat IDs can be configured later via the web UI.
# The Claudible API key and base URL are read from .env (shared by all bots).
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
    echo "Usage: ./deploy-bot-simple.sh <bot_name> [model]"
    echo ""
    echo "Examples:"
    echo "  ./deploy-bot-simple.sh alice"
    echo "  ./deploy-bot-simple.sh alice claude-opus-4.6"
    echo ""
    echo "Available models: ${VALID_MODELS[*]}"
    echo "Default model: $DEFAULT_MODEL"
    echo ""
    echo "Telegram token and channels can be configured later via the web UI."
    echo "To deploy with a token now, use: ./deploy-bot.sh <name> <token> [chat_ids] [model]"
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

# --- Read shared config from .env ---
if [ -f "$SCRIPT_DIR/.env" ]; then
    CLAUDIBLE_KEY=$(grep '^CLAUDIBLE_API_KEY=' "$SCRIPT_DIR/.env" | cut -d'=' -f2-)
    CLAUDIBLE_URL=$(grep '^CLAUDIBLE_BASE_URL=' "$SCRIPT_DIR/.env" | cut -d'=' -f2-)
fi

if [ -z "${CLAUDIBLE_KEY:-}" ]; then
    echo "❌ CLAUDIBLE_API_KEY not found in .env"
    echo "   Add this line to .env: CLAUDIBLE_API_KEY=your-api-key-here"
    exit 1
fi

if [ -z "${CLAUDIBLE_URL:-}" ]; then
    echo "❌ CLAUDIBLE_BASE_URL not found in .env"
    echo "   Add this line to .env: CLAUDIBLE_BASE_URL=https://aisieure.com"
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

sed -e "s|YOUR_TELEGRAM_BOT_TOKEN|${TELEGRAM_TOKEN}|g" \
    -e "s|YOUR_CLAUDIBLE_API_KEY|${CLAUDIBLE_KEY}|g" \
    -e "s|CLAUDIBLE_BASE_URL|${CLAUDIBLE_URL}|g" \
    -e "s|YOUR_SECRET_TOKEN|${SECRET_TOKEN}|g" \
    -e "s|\[\"ALLOWED_CHAT_IDS\"\]|[]|g" \
    -e "s|SELECTED_MODEL|${MODEL}|g" \
    "$TEMPLATE" > "$BOTS_DIR/$BOT_NAME/config.json"

# --- Inject bot's domain into allowedOrigins ---
NGINX_ENV_FILE="$SCRIPT_DIR/../nginx/.env"
if [ -f "$NGINX_ENV_FILE" ]; then
    BOT_DOMAIN=$(grep '^DOMAIN=' "$NGINX_ENV_FILE" | cut -d'=' -f2-)
fi
if [ -n "${BOT_DOMAIN:-}" ]; then
    sed -i "s|\"allowedOrigins\": \[\"http://localhost:18789\"\]|\"allowedOrigins\": [\"http://localhost:18789\", \"https://${BOT_NAME}.${BOT_DOMAIN}\"]|" \
        "$BOTS_DIR/$BOT_NAME/config.json"
fi

echo "✅ Generated bots/$BOT_NAME/config.json (model: $MODEL)"

# --- Register port ---
echo "$BOT_NAME $NEXT_OFFSET" >> "$PORT_REGISTRY"
echo "✅ Registered port offset $NEXT_OFFSET (external port: $EXTERNAL_PORT)"

# --- Update .env (no token to store) ---
ENV_VAR_SUFFIX=$(echo "$BOT_NAME" | tr '[:lower:]-' '[:upper:]_')
cat >> "$SCRIPT_DIR/.env" << EOF

# Bot: $BOT_NAME
TOKEN_${ENV_VAR_SUFFIX}=
EOF
echo "✅ Added TOKEN_${ENV_VAR_SUFFIX} to .env (empty — set via UI later)"

# --- Regenerate docker-compose.yml ---
"$SCRIPT_DIR/generate-compose.sh"

# --- Build and start ONLY this bot ---
docker compose -f "$SCRIPT_DIR/docker-compose.yml" build "openclaw-bot-${BOT_NAME}"
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d --no-deps "openclaw-bot-${BOT_NAME}"

# --- Reload nginx ---
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
echo "⚠️  No Telegram token set. Configure it via the dashboard:"
if [ -n "$DEPLOY_DOMAIN" ]; then
    echo "   https://${BOT_NAME}.${DEPLOY_DOMAIN}"
fi
echo ""
echo "📋 View logs: docker compose logs -f openclaw-bot-${BOT_NAME}"
