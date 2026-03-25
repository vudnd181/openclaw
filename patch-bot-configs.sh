#!/bin/bash
set -euo pipefail

# patch-bot-configs.sh — One-time script to add trustedProxies and allowedOrigins
# to all existing bot configs that are missing them.
# Run this once after upgrading to the GUI-enabled setup.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOTS_DIR="$SCRIPT_DIR/bots"
PORT_REGISTRY="$BOTS_DIR/.port-registry"
NGINX_ENV="$SCRIPT_DIR/../nginx/.env"

if [ -f "$NGINX_ENV" ]; then
    DOMAIN=$(grep '^DOMAIN=' "$NGINX_ENV" | cut -d'=' -f2-)
fi

if [ -z "${DOMAIN:-}" ]; then
    echo "❌ DOMAIN not set in nginx/.env"
    exit 1
fi

if [ ! -f "$PORT_REGISTRY" ] || [ ! -s "$PORT_REGISTRY" ]; then
    echo "⚠️  No bots registered."
    exit 0
fi

PATCHED=0

while IFS=' ' read -r bot_name port_offset; do
    [[ -z "$bot_name" || "$bot_name" == \#* ]] && continue

    CONFIG="$BOTS_DIR/$bot_name/config.json"
    if [ ! -f "$CONFIG" ]; then
        echo "⚠️  Skipping $bot_name — no config.json"
        continue
    fi

    CHANGED=false

    # 1. Add trustedProxies if missing
    if ! grep -q '"trustedProxies"' "$CONFIG"; then
        sed -i 's|"bind": "lan",|"bind": "lan",\n    "trustedProxies": ["172.16.0.0/12", "10.0.0.0/8", "192.168.0.0/16"],|' "$CONFIG"
        CHANGED=true
        echo "  ✅ $bot_name: added trustedProxies"
    else
        echo "  ⏭️  $bot_name: trustedProxies already present"
    fi

    # 2. Add bot's HTTPS origin to allowedOrigins if missing
    BOT_ORIGIN="https://${bot_name}.${DOMAIN}"
    if ! grep -q "$BOT_ORIGIN" "$CONFIG"; then
        sed -i "s|\"allowedOrigins\": \[\"http://localhost:18789\"\]|\"allowedOrigins\": [\"http://localhost:18789\", \"${BOT_ORIGIN}\"]|" "$CONFIG"
        CHANGED=true
        echo "  ✅ $bot_name: added $BOT_ORIGIN to allowedOrigins"
    else
        echo "  ⏭️  $bot_name: allowedOrigins already has $BOT_ORIGIN"
    fi

    if [ "$CHANGED" = true ]; then
        PATCHED=$((PATCHED + 1))
    fi

done < "$PORT_REGISTRY"

echo ""
echo "✅ Patched $PATCHED bot config(s)"
echo ""
if [ "$PATCHED" -gt 0 ]; then
    echo "Now restart affected bots:"
    echo "  docker compose up -d"
fi
