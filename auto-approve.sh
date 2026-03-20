#!/bin/bash
set -euo pipefail

# auto-approve.sh — Auto-approve pending device pairing requests for OpenClaw bots
# Usage:
#   ./auto-approve.sh <bot_name>          # Approve pending devices for one bot
#   ./auto-approve.sh <bot_name> --wait   # Wait 60s for browser to connect
#   ./auto-approve.sh --all               # Run forever, auto-approve ALL bots (daemon)
#
# Examples:
#   ./auto-approve.sh vu                  # Approve all pending devices now
#   ./auto-approve.sh vu --wait           # Wait for browser to connect, then approve
#   ./auto-approve.sh --all               # Background daemon for all bots
#   nohup ./auto-approve.sh --all &       # Run as background daemon

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOTS_DIR="$SCRIPT_DIR/bots"
PORT_REGISTRY="$BOTS_DIR/.port-registry"

# Read domain from nginx/.env
NGINX_ENV="$SCRIPT_DIR/../nginx/.env"
DOMAIN=""
if [ -f "$NGINX_ENV" ]; then
    DOMAIN=$(grep '^DOMAIN=' "$NGINX_ENV" | cut -d'=' -f2- || true)
fi

# --- Helper: approve pending devices for a given container ---
approve_pending_for() {
    local service_name="$1"
    local bot_name="$2"

    # Check container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${service_name}$"; then
        return 1
    fi

    local output
    output=$(docker exec -u node "$service_name" /usr/local/bin/openclaw devices list 2>/dev/null || true)

    if [ -z "$output" ]; then
        return 1
    fi

    # Extract request IDs from pending entries
    local request_ids
    request_ids=$(echo "$output" | grep -i "pending\|request\|waiting" | grep -oE '[a-f0-9-]{8,}' || true)

    if [ -z "$request_ids" ]; then
        request_ids=$(echo "$output" | grep -oE '[a-f0-9-]{8,}' || true)
    fi

    if [ -z "$request_ids" ]; then
        return 1
    fi

    local count=0
    while IFS= read -r req_id; do
        [ -z "$req_id" ] && continue
        if docker exec -u node "$service_name" /usr/local/bin/openclaw devices approve "$req_id" 2>/dev/null; then
            echo "[$(date '+%H:%M:%S')] ✅ [$bot_name] Approved device: $req_id"
            count=$((count + 1))
        fi
    done <<< "$request_ids"

    [ "$count" -gt 0 ] && return 0
    return 1
}

# --- Helper: show gateway info for a bot ---
show_bot_info() {
    local service_name="$1"
    local bot_name="$2"

    echo "🔑 Bot '$bot_name':"
    local token
    token=$(docker exec -u node "$service_name" cat /home/node/.openclaw/openclaw.json 2>/dev/null | grep -oP '"token"\s*:\s*"\K[^"]+' || echo "")
    if [ -n "$token" ]; then
        echo "   Token: ${token}"
    fi
    if [ -n "$DOMAIN" ]; then
        echo "   Dashboard: https://${bot_name}.${DOMAIN}"
    fi
}

# =============================================================
# MODE: --all (daemon — run forever for all bots)
# =============================================================
if [ "${1:-}" = "--all" ]; then
    if [ ! -f "$PORT_REGISTRY" ] || [ ! -s "$PORT_REGISTRY" ]; then
        echo "❌ No bots registered in .port-registry"
        exit 1
    fi

    echo "🤖 Auto-approve daemon started"
    echo "   Monitoring ALL bots for device pairing requests"
    echo "   Checking every 5 seconds"
    echo "   Press Ctrl+C to stop"
    echo ""

    # Show all bots info
    while IFS=' ' read -r bot_name port_offset; do
        [[ -z "$bot_name" || "$bot_name" == \#* ]] && continue
        service_name="openclaw-bot-${bot_name}"
        if docker ps --format '{{.Names}}' | grep -q "^${service_name}$"; then
            show_bot_info "$service_name" "$bot_name"
        else
            echo "⚠️  Bot '$bot_name' — container not running"
        fi
    done < "$PORT_REGISTRY"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Infinite loop — check all bots every 5 seconds
    while true; do
        while IFS=' ' read -r bot_name port_offset; do
            [[ -z "$bot_name" || "$bot_name" == \#* ]] && continue
            service_name="openclaw-bot-${bot_name}"
            approve_pending_for "$service_name" "$bot_name" 2>/dev/null || true
        done < "$PORT_REGISTRY"
        sleep 5
    done

    exit 0
fi

# =============================================================
# MODE: single bot
# =============================================================
BOT_NAME="${1:-}"
WAIT_MODE="${2:-}"

if [ -z "$BOT_NAME" ]; then
    echo "Usage: ./auto-approve.sh <bot_name> [--wait]"
    echo "       ./auto-approve.sh --all"
    echo ""
    echo "Options:"
    echo "  --wait  Wait up to 60s for new device requests (use after opening dashboard)"
    echo "  --all   Run forever, auto-approve for ALL bots (daemon mode)"
    echo ""
    echo "Examples:"
    echo "  ./auto-approve.sh vu           # Approve all pending now"
    echo "  ./auto-approve.sh vu --wait    # Wait for browser, then approve"
    echo "  ./auto-approve.sh --all        # Daemon for all bots"
    echo "  nohup ./auto-approve.sh --all &  # Run in background"
    exit 1
fi

SERVICE_NAME="openclaw-bot-${BOT_NAME}"

# Check container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$"; then
    echo "❌ Container '$SERVICE_NAME' is not running."
    exit 1
fi

# Show gateway info
show_bot_info "$SERVICE_NAME" "$BOT_NAME"
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
        if approve_pending_for "$SERVICE_NAME" "$BOT_NAME"; then
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
    if approve_pending_for "$SERVICE_NAME" "$BOT_NAME"; then
        echo ""
        echo "🎉 All pending devices approved!"
    else
        echo "ℹ️  No pending device requests found."
        echo "   Open the dashboard first, then run:"
        echo "   ./auto-approve.sh $BOT_NAME --wait"
    fi
fi
