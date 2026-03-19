#!/bin/bash
set -euo pipefail

# deploy-bot.sh — Deploy a new OpenClaw bot instance
# Usage: ./deploy-bot.sh <bot_name> <telegram_token> <chat_ids>
# Example: ./deploy-bot.sh alice 123456:ABC 658635669,123456789
#
# The Claudible API key is read from CLAUDIBLE_API_KEY in .env (shared by all bots).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOTS_DIR="$SCRIPT_DIR/bots"
PORT_REGISTRY="$BOTS_DIR/.port-registry"
TEMPLATE="$SCRIPT_DIR/config.bot.template.json"
BASE_PORT=18789

# --- Argument Parsing ---
BOT_NAME="${1:-}"
TELEGRAM_TOKEN="${2:-}"
CHAT_IDS="${3:-}"

if [ -z "$BOT_NAME" ] || [ -z "$TELEGRAM_TOKEN" ] || [ -z "$CHAT_IDS" ]; then
    echo "Usage: ./deploy-bot.sh <bot_name> <telegram_token> <chat_ids>"
    echo ""
    echo "Arguments:"
    echo "  bot_name        Unique name for the bot (e.g., alice, support-bot)"
    echo "  telegram_token  Telegram bot token from @BotFather"
    echo "  chat_ids        Comma-separated Telegram user/chat IDs to allow"
    echo ""
    echo "The Claudible API key is read from CLAUDIBLE_API_KEY in .env"
    echo ""
    echo "Examples:"
    echo "  ./deploy-bot.sh alice 123456:ABC 658635669"
    echo "  ./deploy-bot.sh alice 123456:ABC 658635669,123456789,987654321"
    exit 1
fi

# --- Validate bot name (lowercase alphanumeric + hyphens) ---
if [[ ! "$BOT_NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    echo "❌ Bot name must be lowercase alphanumeric with optional hyphens (e.g., 'alice', 'support-bot')"
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

# Convert comma-separated IDs to JSON array format: 123,456 → "123","456"
ALLOW_FROM_JSON=$(echo "$CHAT_IDS" | sed 's/,/","/g')

sed -e "s|YOUR_TELEGRAM_BOT_TOKEN|${TELEGRAM_TOKEN}|g" \
    -e "s|YOUR_CLAUDIBLE_API_KEY|${CLAUDIBLE_KEY}|g" \
    -e "s|YOUR_SECRET_TOKEN|${SECRET_TOKEN}|g" \
    -e "s|ALLOWED_CHAT_IDS|${ALLOW_FROM_JSON}|g" \
    "$TEMPLATE" > "$BOTS_DIR/$BOT_NAME/config.json"

echo "✅ Generated bots/$BOT_NAME/config.json"

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

echo ""
echo "🚀 Bot '$BOT_NAME' is now running!"
echo "   Container: openclaw-bot-${BOT_NAME}"
echo "   Port:      $EXTERNAL_PORT → 18789 (internal)"
echo "   Config:    bots/$BOT_NAME/config.json"
echo ""
echo "📋 View logs: docker compose logs -f openclaw-bot-${BOT_NAME}"
