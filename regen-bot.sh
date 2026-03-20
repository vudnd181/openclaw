#!/bin/bash
set -euo pipefail

# regen-bot.sh — Regenerate a bot's config.json from the updated template
# Preserves existing: Telegram token, API key, chat IDs, secret token
# Usage: ./regen-bot.sh <bot_name>
#        ./regen-bot.sh          (regenerates ALL bots)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOTS_DIR="$SCRIPT_DIR/bots"
TEMPLATE="$SCRIPT_DIR/config.bot.template.json"

regen_one() {
    local BOT_NAME="$1"
    local BOT_DIR="$BOTS_DIR/$BOT_NAME"
    local CONFIG="$BOT_DIR/config.json"

    if [ ! -f "$CONFIG" ]; then
        echo "❌ No config.json found for bot '$BOT_NAME' at $CONFIG"
        return 1
    fi

    # --- Extract existing values from current config.json ---
    TELEGRAM_TOKEN=$(python3 -c "import json,sys; d=json.load(open('$CONFIG')); print(d['env']['TELEGRAM_BOT_TOKEN'])")
    SECRET_TOKEN=$(python3 -c "import json,sys; d=json.load(open('$CONFIG')); print(d['gateway']['auth']['token'])")

    # Extract allowFrom chat IDs (first account's list) as comma-separated string
    CHAT_IDS=$(python3 -c "
import json
d = json.load(open('$CONFIG'))
ids = d.get('channels', {}).get('telegram', {}).get('allowFrom', [])
print(','.join(str(i) for i in ids))
")

    # --- Read shared API key from .env ---
    CLAUDIBLE_KEY=$(grep '^CLAUDIBLE_API_KEY=' "$SCRIPT_DIR/.env" | cut -d'=' -f2-)

    if [ -z "$CLAUDIBLE_KEY" ]; then
        echo "❌ CLAUDIBLE_API_KEY not found in .env"
        return 1
    fi

    # --- Convert comma-separated IDs to JSON array format: 123,456 → "123","456" ---
    ALLOW_FROM_JSON=$(echo "$CHAT_IDS" | sed 's/,/","/g')

    # --- Backup old config ---
    cp "$CONFIG" "$CONFIG.bak"

    # --- Regenerate config from template ---
    sed -e "s|YOUR_TELEGRAM_BOT_TOKEN|${TELEGRAM_TOKEN}|g" \
        -e "s|YOUR_CLAUDIBLE_API_KEY|${CLAUDIBLE_KEY}|g" \
        -e "s|YOUR_SECRET_TOKEN|${SECRET_TOKEN}|g" \
        -e "s|ALLOWED_CHAT_IDS|${ALLOW_FROM_JSON}|g" \
        "$TEMPLATE" > "$CONFIG"

    echo "✅ Regenerated bots/$BOT_NAME/config.json (backup: config.json.bak)"
}

# --- Main ---
if [ -n "${1:-}" ]; then
    # Regenerate single bot
    regen_one "$1"
else
    # Regenerate ALL bots from port registry
    PORT_REGISTRY="$BOTS_DIR/.port-registry"
    if [ ! -f "$PORT_REGISTRY" ] || [ ! -s "$PORT_REGISTRY" ]; then
        echo "⚠️  No bots registered."
        exit 0
    fi

    COUNT=0
    while IFS=' ' read -r bot_name _; do
        [[ -z "$bot_name" || "$bot_name" == \#* ]] && continue
        regen_one "$bot_name"
        COUNT=$((COUNT + 1))
    done < "$PORT_REGISTRY"

    echo ""
    echo "✅ Regenerated $COUNT bot(s) from template"
fi

echo ""
echo "🔄 Restart affected bots to apply:"
echo "   docker compose up -d --no-deps openclaw-bot-<name>"
echo "   or: docker compose up -d --build   (for all bots)"
