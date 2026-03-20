#!/bin/bash
set -euo pipefail

# auto-approve.sh — Auto-approve pending device pairing requests for OpenClaw bots
# Usage: ./auto-approve.sh <bot_name> [--wait]
#
# Without --wait: Approve all currently pending devices and exit
# With --wait:    Wait up to 60s for a new device request, then approve it
#
# Examples:
#   ./auto-approve.sh vu                # Approve all pending devices now
#   ./auto-approve.sh vu --wait         # Wait for browser to connect, then approve

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BOT_NAME="${1:-}"
WAIT_MODE="${2:-}"

if [ -z "$BOT_NAME" ]; then
    echo "Usage: ./auto-approve.sh <bot_name> [--wait]"
    echo ""
    echo "Options:"
    echo "  --wait  Wait up to 60s for new device requests (use after opening dashboard)"
    echo ""
    echo "Examples:"
    echo "  ./auto-approve.sh vu           # Approve all pending now"
    echo "  ./auto-approve.sh vu --wait    # Wait for browser, then approve"
    exit 1
fi

SERVICE_NAME="openclaw-bot-${BOT_NAME}"

# Check container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$"; then
    echo "❌ Container '$SERVICE_NAME' is not running."
    exit 1
fi

approve_pending() {
    # List pending devices and extract request IDs
    local output
    output=$(docker exec -u node "$SERVICE_NAME" /usr/local/bin/openclaw devices list 2>/dev/null || true)

    if [ -z "$output" ]; then
        return 1
    fi

    # Extract request IDs from pending entries
    local request_ids
    request_ids=$(echo "$output" | grep -i "pending\|request\|waiting" | grep -oE '[a-f0-9-]{8,}' || true)

    if [ -z "$request_ids" ]; then
        # Try alternative: approve all listed device IDs
        request_ids=$(echo "$output" | grep -oE '[a-f0-9-]{8,}' || true)
    fi

    if [ -z "$request_ids" ]; then
        return 1
    fi

    local count=0
    while IFS= read -r req_id; do
        [ -z "$req_id" ] && continue
        if docker exec -u node "$SERVICE_NAME" /usr/local/bin/openclaw devices approve "$req_id" 2>/dev/null; then
            echo "✅ Approved device: $req_id"
            count=$((count + 1))
        fi
    done <<< "$request_ids"

    if [ "$count" -gt 0 ]; then
        return 0
    fi
    return 1
}

# --- Get gateway token for display ---
echo "🔑 Gateway info for bot '$BOT_NAME':"
GATEWAY_TOKEN=$(docker exec -u node "$SERVICE_NAME" cat /home/node/.openclaw/openclaw.json 2>/dev/null | grep -oP '"token"\s*:\s*"\K[^"]+' || echo "")
if [ -n "$GATEWAY_TOKEN" ]; then
    echo "   Token: ${GATEWAY_TOKEN:0:8}...${GATEWAY_TOKEN: -4}"
fi

# Read domain for dashboard URL
NGINX_ENV="$SCRIPT_DIR/../nginx/.env"
if [ -f "$NGINX_ENV" ]; then
    DOMAIN=$(grep '^DOMAIN=' "$NGINX_ENV" | cut -d'=' -f2-)
fi
if [ -n "${DOMAIN:-}" ]; then
    echo "   Dashboard: https://${BOT_NAME}.${DOMAIN}"
fi
echo ""

if [ "$WAIT_MODE" = "--wait" ]; then
    # --- Wait mode: poll for new device requests ---
    echo "⏳ Waiting for device pairing request (open dashboard in browser)..."
    echo "   Timeout: 60 seconds"
    echo "   Press Ctrl+C to cancel"
    echo ""

    TIMEOUT=60
    ELAPSED=0
    INTERVAL=3

    while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
        if approve_pending; then
            echo ""
            echo "🎉 Device paired successfully! Dashboard is ready."
            exit 0
        fi
        sleep "$INTERVAL"
        ELAPSED=$((ELAPSED + INTERVAL))
        printf "\r   Checking... (%ds/%ds)" "$ELAPSED" "$TIMEOUT"
    done

    echo ""
    echo "⏰ Timeout — no device request found."
    echo "   Make sure you opened the dashboard in your browser."
    echo "   Try again: ./auto-approve.sh $BOT_NAME --wait"
    exit 1
else
    # --- Immediate mode: approve all pending now ---
    echo "🔍 Checking for pending device requests..."
    if approve_pending; then
        echo ""
        echo "🎉 All pending devices approved!"
    else
        echo "ℹ️  No pending device requests found."
        echo "   Open the dashboard first, then run:"
        echo "   ./auto-approve.sh $BOT_NAME --wait"
    fi
fi
