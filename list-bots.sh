#!/bin/bash
set -euo pipefail

# list-bots.sh — Show all registered bots and their status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOTS_DIR="$SCRIPT_DIR/bots"
PORT_REGISTRY="$BOTS_DIR/.port-registry"
BASE_PORT=18789

if [ ! -f "$PORT_REGISTRY" ] || [ ! -s "$PORT_REGISTRY" ]; then
    echo "No bots registered. Deploy one with:"
    echo "  ./deploy-bot.sh <name> <telegram_token> <chat_ids>"
    exit 0
fi

echo "┌──────────────────┬───────┬────────────┬──────────────────────────┐"
echo "│ Bot Name         │ Port  │ Status     │ Container                │"
echo "├──────────────────┼───────┼────────────┼──────────────────────────┤"

BOT_COUNT=0

while IFS=' ' read -r bot_name port_offset; do
    [[ -z "$bot_name" || "$bot_name" == \#* ]] && continue

    EXTERNAL_PORT=$((BASE_PORT + port_offset - 1))
    SERVICE_NAME="openclaw-bot-${bot_name}"

    # Check container status
    STATUS=$(docker inspect --format='{{.State.Status}}' "$SERVICE_NAME" 2>/dev/null || echo "not found")

    # Format the status
    case "$STATUS" in
        running)   STATUS_DISPLAY="✅ running " ;;
        exited)    STATUS_DISPLAY="⏹️  exited  " ;;
        created)   STATUS_DISPLAY="🔵 created " ;;
        *)         STATUS_DISPLAY="❌ $STATUS" ;;
    esac

    printf "│ %-16s │ %5d │ %-10s │ %-24s │\n" \
        "$bot_name" "$EXTERNAL_PORT" "$STATUS_DISPLAY" "$SERVICE_NAME"

    BOT_COUNT=$((BOT_COUNT + 1))

done < "$PORT_REGISTRY"

echo "└──────────────────┴───────┴────────────┴──────────────────────────┘"
echo ""
echo "Total: ${BOT_COUNT} bot(s)"
